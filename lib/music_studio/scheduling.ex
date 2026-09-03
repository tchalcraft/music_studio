defmodule MusicStudio.Scheduling do
  @moduledoc """
  Online lesson booking: computes availability from the Google Availability calendar,
  books a slot as a `Teaching.Lesson` (with a prospective `Student`), writes the calendar
  event, and sends Resend confirmation/notification emails. The DB exclusion constraint is
  the hard double-booking guarantee; the Google + email work are best-effort side effects
  performed after the booking commits.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias MusicStudio.{Analytics, Catalog, Repo, Teaching}
  alias MusicStudio.Scheduling.{Availability, Credentials, GoogleCalendar, Notifier, Recurrence}
  alias MusicStudio.Teaching.Enrollment
  alias MusicStudio.Teaching.Lesson

  require Logger

  @spec list_available_slots(map()) :: {:ok, [Availability.Slot.t()]} | {:error, term()}
  def list_available_slots(%{
        instrument_slug: _slug,
        duration_minutes: duration,
        from: from_date,
        to: to_date
      }) do
    time_min = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
    time_max = DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC")

    slots =
      Availability.compute(%{
        # Availability is the studio's working hours (Mon–Fri 2–9pm), not a Google calendar.
        blocks: working_hour_blocks(from_date, to_date),
        booked: booked_intervals(time_min, time_max) ++ held_intervals(time_min, time_max),
        duration_minutes: duration,
        grid_minutes: cfg(:slot_grid_minutes),
        buffer_minutes: cfg(:buffer_minutes),
        min_notice_minutes: cfg(:min_notice_minutes),
        now: DateTime.utc_now()
      })

    {:ok, slots}
  end

  # One block per working day in the range, from working_start to working_end (studio tz),
  # in UTC for Availability.compute. Lessons must fit inside, so none can run past the end.
  defp working_hour_blocks(from_date, to_date) do
    tz = cfg(:studio_timezone)
    days = cfg(:working_days)
    wstart = cfg(:working_start)
    wend = cfg(:working_end)

    from_date
    |> Date.range(to_date)
    |> Enum.filter(&(Date.day_of_week(&1) in days))
    |> Enum.map(fn date ->
      %{
        starts_at: date |> DateTime.new!(wstart, tz) |> DateTime.shift_zone!("Etc/UTC"),
        ends_at: date |> DateTime.new!(wend, tz) |> DateTime.shift_zone!("Etc/UTC")
      }
    end)
  end

  @spec preview_series(map()) :: {:ok, map()} | {:error, term()}
  def preview_series(%{
        instrument_slug: slug,
        duration_minutes: duration,
        first_starts_at: first_starts_at,
        interval_weeks: interval_weeks
      }) do
    tz = cfg(:studio_timezone)
    local_first = DateTime.shift_zone!(first_starts_at, tz)
    start_date = DateTime.to_date(local_first)
    time = local_first |> DateTime.to_time() |> Time.truncate(:second)
    term_end = Recurrence.term_end(start_date)

    {bookable, conflicted} =
      start_date
      |> Recurrence.occurrence_dates(interval_weeks, term_end)
      |> Enum.split_with(&week_bookable?(&1, time, tz, slug, duration))

    {:ok,
     %{
       start_date: start_date,
       interval_weeks: interval_weeks,
       term_end: term_end,
       bookable: Enum.map(bookable, &Recurrence.occurrence_utc(&1, time, tz)),
       conflicted: Enum.map(conflicted, &Recurrence.occurrence_utc(&1, time, tz))
     }}
  end

  defp week_bookable?(date, time, tz, slug, duration) do
    starts = Recurrence.occurrence_utc(date, time, tz)
    slot_bookable?(slug, duration, date, starts)
  end

  # True if `starts` is one of the slots availability offers for that single day.
  defp slot_bookable?(slug, duration, date, starts) do
    {:ok, slots} =
      list_available_slots(%{
        instrument_slug: slug,
        duration_minutes: duration,
        from: date,
        to: date
      })

    Enum.any?(slots, &(DateTime.compare(&1.starts_at, starts) == :eq))
  end

  @spec create_series(map()) :: {:ok, map()} | {:error, term()}
  def create_series(params) do
    with {:ok, teacher} <- fetch_teacher(),
         {:ok, instrument} <- fetch_instrument(params.instrument_slug),
         {:ok, offering} <- fetch_offering(params.duration_minutes),
         {:ok, preview} <- preview_series(params) do
      tz = cfg(:studio_timezone)
      local_first = DateTime.shift_zone!(params.first_starts_at, tz)

      series = %{
        teacher: teacher,
        instrument: instrument,
        offering: offering,
        preview: preview,
        weekday: Date.day_of_week(DateTime.to_date(local_first)),
        time: local_first |> DateTime.to_time() |> Time.truncate(:second),
        tz: tz
      }

      case Repo.transaction(series_multi(params, series)) do
        {:ok, %{enrollment: enr} = changes} ->
          lessons = collect_lessons(changes)
          after_series(enr, lessons, series, params)
          {:ok, %{enrollment: enr, lessons: lessons, conflicted: preview.conflicted}}

        {:error, _step, %Ecto.Changeset{errors: errors}, _} ->
          booking_error(errors)

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp series_multi(params, series) do
    base =
      Multi.new()
      |> Multi.run(:student, fn _repo, _ -> upsert_student(params) end)
      |> Multi.insert(:enrollment, fn %{student: student} ->
        series_enrollment_changeset(params, series, student)
      end)

    series.preview.bookable
    |> Enum.with_index()
    |> Enum.reduce(base, fn {starts_at, i}, multi ->
      Multi.insert(multi, {:lesson, i}, fn %{student: student, enrollment: enrollment} ->
        series_lesson_changeset(params, series, student, enrollment, starts_at)
      end)
    end)
  end

  defp series_enrollment_changeset(params, series, student) do
    Enrollment.changeset(%Enrollment{}, %{
      status: :active,
      started_on: series.preview.start_date,
      ended_on: series.preview.term_end,
      recurrence_interval_weeks: series.preview.interval_weeks,
      recurrence_weekday: series.weekday,
      recurrence_time: series.time,
      recurrence_timezone: series.tz,
      booking_token: gen_token(),
      contact_email: params.email,
      teacher_id: series.teacher.id,
      student_id: student.id,
      instrument_id: series.instrument.id,
      offering_id: series.offering.id
    })
  end

  defp series_lesson_changeset(params, series, student, enrollment, starts_at) do
    ends_at = DateTime.add(starts_at, params.duration_minutes, :minute)

    Lesson.changeset(%Lesson{}, %{
      scheduled_start: DateTime.truncate(starts_at, :second),
      scheduled_end: DateTime.truncate(ends_at, :second),
      duration_minutes: params.duration_minutes,
      status: :scheduled,
      price_cents: series.offering.price_cents,
      currency: series.offering.currency,
      teacher_id: series.teacher.id,
      student_id: student.id,
      instrument_id: series.instrument.id,
      offering_id: series.offering.id,
      enrollment_id: enrollment.id,
      booking_token: gen_token()
    })
  end

  defp collect_lessons(changes) do
    changes
    |> Enum.filter(fn {k, _v} -> match?({:lesson, _}, k) end)
    |> Enum.sort_by(fn {{:lesson, i}, _v} -> i end)
    |> Enum.map(fn {_k, lesson} -> lesson end)
  end

  defp after_series(enrollment, lessons, series, params) do
    Enum.each(lessons, fn lesson ->
      side_effect(fn ->
        ends_at = DateTime.add(lesson.scheduled_start, lesson.duration_minutes, :minute)
        write_event(lesson, series.instrument, params, ends_at)
      end)
    end)

    side_effect(fn ->
      Notifier.deliver_series_emails(series_email_details(enrollment, lessons, series, params))
    end)

    side_effect(fn ->
      Analytics.record_event(%{
        verb: "series_booked",
        subject_type: "enrollment",
        subject_id: enrollment.id,
        metadata: %{
          "instrument" => params.instrument_slug,
          "interval_weeks" => series.preview.interval_weeks,
          "lessons" => length(lessons),
          "conflicted" => length(series.preview.conflicted)
        }
      })
    end)

    :ok
  end

  defp series_email_details(enrollment, lessons, series, params) do
    %{
      visitor_name: params.name,
      visitor_email: params.email,
      instrument: String.downcase(series.instrument.name),
      interval_weeks: series.preview.interval_weeks,
      lesson_starts: Enum.map(lessons, & &1.scheduled_start),
      conflicted: series.preview.conflicted,
      manage_url: MusicStudioWeb.Endpoint.url() <> "/book/manage/" <> enrollment.booking_token,
      timezone: series.tz
    }
  end

  @spec create_booking(map()) :: {:ok, Lesson.t()} | {:error, term()}
  def create_booking(params) do
    with {:ok, teacher} <- fetch_teacher(),
         {:ok, instrument} <- fetch_instrument(params.instrument_slug),
         {:ok, offering} <- fetch_offering(params.duration_minutes) do
      ends_at = DateTime.add(params.starts_at, params.duration_minutes, :minute)

      multi =
        Multi.new()
        |> Multi.run(:student, fn _repo, _ -> upsert_student(params) end)
        |> Multi.insert(:lesson, fn %{student: student} ->
          Lesson.changeset(%Lesson{}, %{
            scheduled_start: DateTime.truncate(params.starts_at, :second),
            scheduled_end: DateTime.truncate(ends_at, :second),
            duration_minutes: params.duration_minutes,
            status: :scheduled,
            price_cents: offering.price_cents,
            currency: offering.currency,
            teacher_id: teacher.id,
            student_id: student.id,
            instrument_id: instrument.id,
            offering_id: offering.id,
            booking_token: gen_token()
          })
        end)

      case Repo.transaction(multi) do
        {:ok, %{lesson: lesson}} ->
          {:ok, after_booking(lesson, teacher, instrument, params, ends_at)}

        {:error, :lesson, %Ecto.Changeset{errors: errors}, _} ->
          booking_error(errors)

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @spec cancel_booking(String.t()) :: {:ok, Lesson.t()} | {:error, term()}
  def cancel_booking(token) do
    case get_lesson_by_token(token) do
      nil -> {:error, :not_found}
      lesson -> do_cancel(lesson)
    end
  end

  defp do_cancel(lesson) do
    {:ok, cancelled} = cancel_lesson_record(lesson)
    side_effect(fn -> Notifier.deliver_cancellation(lesson_email_details(lesson)) end)
    {:ok, cancelled}
  end

  # Cancels one lesson's DB row + Google event, WITHOUT emailing. Touches no associations,
  # so it is safe on non-preloaded lessons (used for bulk series cancel/pause, which send at
  # most a single series-level message rather than one email per lesson).
  defp cancel_lesson_record(lesson) do
    {:ok, cancelled} =
      lesson
      |> Lesson.changeset(%{status: :cancelled, deleted_at: DateTime.utc_now()})
      |> Repo.update()

    delete_event(cancelled)
    {:ok, cancelled}
  end

  @spec reschedule_booking(String.t(), DateTime.t()) :: {:ok, Lesson.t()} | {:error, term()}
  def reschedule_booking(token, new_starts_at) do
    case get_lesson_by_token(token) do
      nil -> {:error, :not_found}
      lesson -> do_reschedule(lesson, new_starts_at)
    end
  end

  defp do_reschedule(lesson, new_starts_at) do
    new_end = DateTime.add(new_starts_at, lesson.duration_minutes, :minute)

    changeset =
      Lesson.changeset(lesson, %{
        scheduled_start: DateTime.truncate(new_starts_at, :second),
        scheduled_end: DateTime.truncate(new_end, :second)
      })

    case Repo.update(changeset) do
      {:ok, updated} ->
        update_event(updated, new_starts_at, new_end)

        side_effect(fn ->
          Notifier.deliver_reschedule(
            lesson_email_details(%{
              lesson
              | scheduled_start: updated.scheduled_start,
                scheduled_end: updated.scheduled_end
            })
          )
        end)

        {:ok, updated}

      {:error, %Ecto.Changeset{errors: errors}} ->
        booking_error(errors)
    end
  end

  defp delete_event(%{google_event_id: nil}), do: :ok

  defp delete_event(lesson) do
    side_effect(fn -> GoogleCalendar.delete_event(target_calendar(), lesson.google_event_id) end)
  end

  defp update_event(%{google_event_id: nil}, _new_starts_at, _new_end), do: :ok

  defp update_event(lesson, new_starts_at, new_end) do
    side_effect(fn ->
      GoogleCalendar.update_event(target_calendar(), lesson.google_event_id, %{
        summary: "Lesson",
        description: "Rescheduled",
        location: "Studio",
        starts_at: new_starts_at,
        ends_at: new_end,
        timezone: cfg(:studio_timezone)
      })
    end)
  end

  @spec get_lesson_by_token(String.t()) :: Lesson.t() | nil
  def get_lesson_by_token(token) do
    Repo.one(
      from l in Lesson,
        where: l.booking_token == ^token,
        preload: [:student, :instrument, :teacher]
    )
  end

  @spec get_series_by_token(String.t()) :: Enrollment.t() | nil
  def get_series_by_token(token), do: Repo.get_by(Enrollment, booking_token: token)

  @spec list_series_lessons(Enrollment.t()) :: [Lesson.t()]
  def list_series_lessons(%Enrollment{id: id}) do
    Repo.all(
      from l in Lesson,
        where: l.enrollment_id == ^id and l.status == :scheduled and is_nil(l.deleted_at),
        order_by: [asc: l.scheduled_start]
    )
  end

  @spec skip_occurrence(String.t()) :: {:ok, Lesson.t()} | {:error, term()}
  def skip_occurrence(lesson_token) do
    case get_lesson_by_token(lesson_token) do
      nil -> {:error, :not_found}
      lesson -> do_cancel(lesson)
    end
  end

  @spec cancel_series(String.t()) :: {:ok, Enrollment.t()} | {:error, term()}
  def cancel_series(series_token) do
    case get_series_by_token(series_token) do
      nil -> {:error, :not_found}
      enrollment -> do_cancel_series(enrollment)
    end
  end

  @pause_max 4

  @spec pause_series(String.t(), Date.t()) :: {:ok, map()} | {:error, term()}
  def pause_series(series_token, from_date) do
    case get_series_by_token(series_token) do
      nil ->
        {:error, :not_found}

      enrollment ->
        skipped =
          enrollment
          |> list_series_lessons()
          |> Enum.filter(&(Date.compare(DateTime.to_date(&1.scheduled_start), from_date) != :lt))
          |> Enum.take(@pause_max)
          |> Enum.map(fn lesson ->
            {:ok, l} = cancel_lesson_record(lesson)
            l
          end)

        {:ok, %{skipped: skipped}}
    end
  end

  defp do_cancel_series(enrollment) do
    Enum.each(list_series_lessons(enrollment), &cancel_lesson_record/1)

    enrollment
    |> Enrollment.changeset(%{status: :cancelled, deleted_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @spec week_alternates(map(), Date.t()) :: {:ok, [Availability.Slot.t()]} | {:error, term()}
  def week_alternates(%{instrument_slug: slug, duration_minutes: duration}, week_of) do
    monday = Date.add(week_of, -(Date.day_of_week(week_of) - 1))

    list_available_slots(%{
      instrument_slug: slug,
      duration_minutes: duration,
      from: monday,
      to: Date.add(monday, 6)
    })
  end

  @spec add_series_lesson(String.t(), DateTime.t()) :: {:ok, Lesson.t()} | {:error, term()}
  def add_series_lesson(series_token, starts_at) do
    with %Enrollment{} = enr <- get_series_by_token(series_token),
         enr <- Repo.preload(enr, :offering),
         ends_at <- DateTime.add(starts_at, enr.offering.duration_minutes, :minute),
         {:ok, lesson} <- Repo.insert(add_series_lesson_changeset(enr, starts_at, ends_at)) do
      side_effect(fn -> add_series_event(enr, lesson, ends_at) end)
      {:ok, lesson}
    else
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{errors: errors}} -> booking_error(errors)
    end
  end

  defp add_series_lesson_changeset(enr, starts_at, ends_at) do
    Lesson.changeset(%Lesson{}, %{
      scheduled_start: DateTime.truncate(starts_at, :second),
      scheduled_end: DateTime.truncate(ends_at, :second),
      duration_minutes: enr.offering.duration_minutes,
      status: :scheduled,
      price_cents: enr.offering.price_cents,
      currency: enr.offering.currency,
      teacher_id: enr.teacher_id,
      student_id: enr.student_id,
      instrument_id: enr.instrument_id,
      offering_id: enr.offering_id,
      enrollment_id: enr.id,
      booking_token: gen_token()
    })
  end

  defp add_series_event(enr, lesson, ends_at) do
    GoogleCalendar.insert_event(target_calendar(), %{
      summary: "Lesson — #{enr.contact_email}",
      description: "Series alternate.",
      location: "Studio",
      starts_at: lesson.scheduled_start,
      ends_at: ends_at,
      timezone: cfg(:studio_timezone)
    })
  end

  # --- internals ---

  defp after_booking(lesson, teacher, instrument, params, ends_at) do
    lesson =
      case side_effect(fn -> write_event(lesson, instrument, params, ends_at) end) do
        {:ok, event_id} ->
          {:ok, updated} =
            lesson |> Lesson.changeset(%{google_event_id: event_id}) |> Repo.update()

          updated

        _ ->
          lesson
      end

    side_effect(fn ->
      Notifier.deliver_booking_emails(email_details(lesson, teacher, instrument, params, ends_at))
    end)

    side_effect(fn ->
      Analytics.record_event(%{
        verb: "lesson_booked",
        subject_type: "lesson",
        subject_id: lesson.id,
        metadata: %{"instrument" => params.instrument_slug, "online" => true}
      })
    end)

    lesson
  end

  defp write_event(lesson, instrument, params, ends_at) do
    GoogleCalendar.insert_event(target_calendar(), %{
      summary: "#{String.capitalize(instrument.name)} lesson — #{params.name}",
      description: "Online booking. #{params.email} #{params.phone}",
      location: "Studio",
      starts_at: lesson.scheduled_start,
      ends_at: ends_at,
      timezone: cfg(:studio_timezone)
    })
  end

  defp email_details(lesson, teacher, instrument, params, ends_at) do
    %{
      visitor_name: params.name,
      visitor_email: params.email,
      instrument: String.downcase(instrument.name),
      starts_at: lesson.scheduled_start,
      ends_at: ends_at,
      duration_minutes: params.duration_minutes,
      manage_url: MusicStudioWeb.Endpoint.url() <> "/book/manage/" <> lesson.booking_token,
      uid: lesson.id,
      organizer_email: teacher.email,
      timezone: cfg(:studio_timezone)
    }
  end

  defp upsert_student(params) do
    case Teaching.get_student_by_email(params.email) do
      nil ->
        [first | rest] = String.split(params.name, " ", parts: 2)

        Teaching.create_student(%{
          first_name: first,
          last_name: List.first(rest),
          email: params.email,
          phone: params.phone,
          status: "prospective"
        })

      student ->
        {:ok, student}
    end
  end

  defp booked_intervals(time_min, time_max) do
    Repo.all(
      from l in Lesson,
        where:
          l.status == :scheduled and is_nil(l.deleted_at) and
            l.scheduled_start < ^time_max and l.scheduled_end > ^time_min,
        select: %{starts_at: l.scheduled_start, ends_at: l.scheduled_end}
    )
  end

  # Recurring slots of active/paused series, projected into the window. These stay reserved
  # even on skipped/paused weeks (no scheduled Lesson row), so the student keeps their time.
  defp held_intervals(time_min, time_max) do
    Enrollment
    |> where([e], e.status in [:active, :paused] and is_nil(e.deleted_at))
    |> where([e], not is_nil(e.recurrence_weekday) and not is_nil(e.recurrence_time))
    |> preload(:offering)
    |> Repo.all()
    |> Enum.flat_map(&series_intervals(&1, time_min, time_max))
  end

  defp series_intervals(enrollment, time_min, time_max) do
    duration = enrollment.offering && enrollment.offering.duration_minutes

    if is_nil(duration) do
      []
    else
      term_end = Recurrence.term_end(enrollment.started_on)

      enrollment.started_on
      |> Recurrence.occurrence_dates(enrollment.recurrence_interval_weeks, term_end)
      |> Enum.map(fn date ->
        starts =
          Recurrence.occurrence_utc(
            date,
            enrollment.recurrence_time,
            enrollment.recurrence_timezone
          )

        %{starts_at: starts, ends_at: DateTime.add(starts, duration, :minute)}
      end)
      |> Enum.filter(fn %{starts_at: s, ends_at: e} ->
        DateTime.compare(s, time_max) == :lt and DateTime.compare(e, time_min) == :gt
      end)
    end
  end

  defp fetch_teacher do
    case Enum.find(Catalog.list_teachers(), & &1.active) do
      nil -> {:error, :no_teacher}
      teacher -> {:ok, teacher}
    end
  end

  defp fetch_instrument(slug) do
    case Enum.find(Catalog.list_instruments(), &(&1.slug == slug)) do
      nil -> {:error, :unknown_instrument}
      instrument -> {:ok, instrument}
    end
  end

  defp fetch_offering(duration) do
    case Enum.find(Catalog.list_offerings(), &(&1.duration_minutes == duration and &1.active)) do
      nil -> {:error, :unknown_offering}
      offering -> {:ok, offering}
    end
  end

  defp booking_error(errors) do
    if Keyword.has_key?(errors, :scheduled_start) do
      {:error, :slot_taken}
    else
      {:error, %Ecto.Changeset{errors: errors, valid?: false}}
    end
  end

  defp side_effect(fun) do
    fun.()
  rescue
    e ->
      Logger.error("booking side effect failed: #{Exception.message(e)}")
      {:error, e}
  end

  defp target_calendar, do: Credentials.target_calendar_id()

  defp lesson_email_details(lesson) do
    %{
      visitor_name: full_name(lesson.student),
      visitor_email: lesson.student.email,
      instrument: (lesson.instrument && String.downcase(lesson.instrument.name)) || "music",
      starts_at: lesson.scheduled_start,
      ends_at: lesson.scheduled_end,
      duration_minutes: lesson.duration_minutes,
      manage_url: MusicStudioWeb.Endpoint.url() <> "/book/manage/" <> lesson.booking_token,
      uid: lesson.id,
      organizer_email: lesson.teacher && lesson.teacher.email,
      timezone: cfg(:studio_timezone)
    }
  end

  defp full_name(%{first_name: f, last_name: nil}), do: f
  defp full_name(%{first_name: f, last_name: l}), do: String.trim("#{f} #{l}")

  defp gen_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp cfg(key),
    do: Keyword.fetch!(Application.get_env(:music_studio, MusicStudio.Scheduling), key)
end
