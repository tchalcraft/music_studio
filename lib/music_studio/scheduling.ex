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
  alias MusicStudio.Scheduling.{Availability, Credentials, GoogleCalendar, Notifier}
  alias MusicStudio.Teaching.Lesson

  require Logger

  @spec list_available_slots(map()) :: {:ok, [Availability.Slot.t()]} | {:error, term()}
  def list_available_slots(%{
        instrument_slug: _slug,
        duration_minutes: duration,
        from: from_date,
        to: to_date
      }) do
    with %{availability_calendar_id: cal} when is_binary(cal) <- Credentials.get(),
         time_min <- DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC"),
         time_max <- DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC"),
         {:ok, blocks} <- GoogleCalendar.list_events(cal, time_min, time_max) do
      slots =
        Availability.compute(%{
          blocks: blocks,
          booked: booked_intervals(time_min, time_max),
          duration_minutes: duration,
          grid_minutes: cfg(:slot_grid_minutes),
          buffer_minutes: cfg(:buffer_minutes),
          min_notice_minutes: cfg(:min_notice_minutes),
          now: DateTime.utc_now()
        })

      {:ok, slots}
    else
      nil -> {:error, :not_connected}
      %{} -> {:error, :not_connected}
      {:error, reason} -> {:error, reason}
    end
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
  def get_lesson_by_token(token), do: Repo.one(from l in Lesson, where: l.booking_token == ^token)

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
      timezone: cfg(:studio_timezone),
      attendee_email: params.email,
      send_updates: "all"
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

  defp target_calendar, do: Credentials.get().target_calendar_id
  defp gen_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp cfg(key),
    do: Keyword.fetch!(Application.get_env(:music_studio, MusicStudio.Scheduling), key)
end
