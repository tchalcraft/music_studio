defmodule MusicStudioWeb.BookingLive do
  @moduledoc """
  Public booking flow, presented as guided steps with a progress bar:
  Lesson → Schedule → Your details → Confirmed. Single LiveView, no route changes.
  """
  use MusicStudioWeb, :live_view

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling

  # Ordered steps as {key, label}; the index drives the progress bar and Back targets.
  @steps [lesson: "Lesson", schedule: "Schedule", details: "Your details", done: "Confirmed"]

  @impl true
  def mount(_params, _session, socket) do
    durations =
      Catalog.list_offerings()
      |> Enum.filter(& &1.active)
      |> Enum.map(& &1.duration_minutes)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok,
     socket
     |> assign(:page_title, "Book a lesson")
     |> assign(:step, :lesson)
     |> assign(:instruments, Catalog.list_instruments())
     |> assign(:durations, durations)
     |> assign(:instrument_slug, nil)
     |> assign(:duration_minutes, nil)
     |> assign(:slots, [])
     |> assign(:slots_by_day, %{})
     |> assign(:slots_error, nil)
     |> assign(:selected_slot, nil)
     |> assign(:selected_day, nil)
     |> assign(:cal_month, nil)
     |> assign(:cadence, "once")
     |> assign(:rec_pattern, nil)
     |> assign(:series_start, nil)
     |> assign(:series_preview, nil)
     |> assign(:booked, nil)
     |> assign(:booked_series, nil)
     |> assign(:form, to_form(%{"name" => "", "email" => "", "phone" => ""}, as: :booking))}
  end

  # Lesson selection is via boxes (pick_instrument / pick_duration). "choose" is retained
  # as a change-based path (and for tests); both share load_and_schedule/1.
  @impl true
  def handle_event("choose", %{"instrument_slug" => slug, "duration_minutes" => dur}, socket)
      when slug != "" and dur != "" do
    {:noreply,
     socket
     |> assign(instrument_slug: slug, duration_minutes: String.to_integer(dur))
     |> load_and_schedule()}
  end

  def handle_event("choose", %{"instrument_slug" => slug, "duration_minutes" => dur}, socket) do
    {:noreply,
     assign(socket,
       instrument_slug: blank_to_nil(slug),
       duration_minutes: parse_duration(dur),
       slots: [],
       selected_slot: nil,
       step: :lesson
     )}
  end

  def handle_event("pick_instrument", %{"slug" => slug}, socket) do
    {:noreply, socket |> assign(:instrument_slug, slug) |> maybe_advance()}
  end

  def handle_event("pick_duration", %{"minutes" => minutes}, socket) do
    {:noreply, socket |> assign(:duration_minutes, String.to_integer(minutes)) |> maybe_advance()}
  end

  def handle_event("set_cadence", %{"cadence" => cadence}, socket) do
    {:noreply,
     socket
     |> assign(
       cadence: cadence,
       selected_day: nil,
       rec_pattern: nil,
       series_start: nil,
       selected_slot: nil
     )
     |> maybe_preview()}
  end

  # Recurring: pick the usual weekday + time, then default the start to that weekday's
  # earliest bookable occurrence and reveal the start-date stepper.
  def handle_event("pick_pattern", %{"start" => iso}, socket) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    weekday = dt |> local_date() |> Date.day_of_week()

    {:noreply,
     socket
     |> assign(rec_pattern: dt, series_start: default_start(weekday))
     |> put_series_slot()
     |> maybe_preview()}
  end

  def handle_event("start_later", _params, socket) do
    {:noreply, socket |> shift_start(7) |> put_series_slot() |> maybe_preview()}
  end

  def handle_event("start_earlier", _params, socket) do
    {:noreply, socket |> shift_start(-7) |> put_series_slot() |> maybe_preview()}
  end

  def handle_event("to_details", _params, socket) do
    {:noreply, assign(socket, :step, :details)}
  end

  def handle_event("pick_day", %{"date" => date}, socket) do
    {:noreply, assign(socket, :selected_day, Date.from_iso8601!(date))}
  end

  def handle_event("prev_month", _params, socket) do
    {:noreply, shift_month(socket, -1)}
  end

  def handle_event("next_month", _params, socket) do
    {:noreply, shift_month(socket, 1)}
  end

  def handle_event("pick_slot", %{"start" => iso}, socket) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    {:noreply, socket |> assign(selected_slot: dt, step: :details) |> maybe_preview()}
  end

  def handle_event("validate_details", %{"booking" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :booking))}
  end

  def handle_event("book", %{"booking" => params}, socket) do
    case socket.assigns.cadence do
      "once" -> book_single(socket, params)
      _ -> book_series(socket, params)
    end
  end

  def handle_event("back", %{"to" => to}, socket) do
    {:noreply, assign(socket, :step, String.to_existing_atom(to))}
  end

  defp book_single(socket, params) do
    attrs = %{
      instrument_slug: socket.assigns.instrument_slug,
      duration_minutes: socket.assigns.duration_minutes,
      starts_at: socket.assigns.selected_slot,
      name: params["name"],
      email: params["email"],
      phone: params["phone"]
    }

    case Scheduling.create_booking(attrs) do
      {:ok, lesson} ->
        {:noreply, assign(socket, booked: lesson, step: :done)}

      {:error, :slot_taken} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry — that time was just taken. Please pick another.")
         |> assign(selected_slot: nil, step: :schedule)}

      {:error, contact} when contact in [:name_required, :email_required] ->
        {:noreply, put_flash(socket, :error, "Please enter your name and email.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  defp book_series(socket, params) do
    attrs = %{
      instrument_slug: socket.assigns.instrument_slug,
      duration_minutes: socket.assigns.duration_minutes,
      first_starts_at: socket.assigns.selected_slot,
      interval_weeks: interval_for(socket.assigns.cadence),
      name: params["name"],
      email: params["email"],
      phone: params["phone"]
    }

    case Scheduling.create_series(attrs) do
      {:ok, %{lessons: lessons, conflicted: conflicted}} ->
        summary = %{count: length(lessons), conflicted: conflicted}
        {:noreply, assign(socket, booked_series: summary, step: :done)}

      {:error, contact} when contact in [:name_required, :email_required] ->
        {:noreply, put_flash(socket, :error, "Please enter your name and email.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  defp maybe_preview(%{assigns: %{cadence: "once"}} = socket),
    do: assign(socket, :series_preview, nil)

  defp maybe_preview(%{assigns: %{selected_slot: nil}} = socket),
    do: assign(socket, :series_preview, nil)

  defp maybe_preview(socket) do
    {:ok, preview} =
      Scheduling.preview_series(%{
        instrument_slug: socket.assigns.instrument_slug,
        duration_minutes: socket.assigns.duration_minutes,
        first_starts_at: socket.assigns.selected_slot,
        interval_weeks: interval_for(socket.assigns.cadence)
      })

    assign(socket, :series_preview, preview)
  end

  defp interval_for("biweekly"), do: 2
  defp interval_for(_), do: 1

  ## Components

  attr :current, :atom, required: true

  def step_bar(assigns) do
    assigns = assign(assigns, :steps, @steps)

    ~H"""
    <ol class="ms-stepbar" aria-label="Booking progress">
      <li
        :for={{{key, label}, idx} <- Enum.with_index(@steps, 1)}
        class={["ms-step", step_status(@current, key)]}
        aria-current={(@current == key && "step") || nil}
      >
        <span class="ms-step-badge">
          <.icon :if={done?(@current, key)} name="hero-check-mini" class="size-4" />
          <span :if={!done?(@current, key)}>{idx}</span>
        </span>
        <span>{label}</span>
      </li>
    </ol>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl p-6">
      <h1 class="text-2xl font-semibold">Book a lesson</h1>

      <.step_bar current={@step} />

      <section :if={@step == :lesson} class="mt-6">
        <h2 class="font-medium">Choose your lesson</h2>

        <p class="mt-3 text-sm font-medium text-gray-500">Instrument</p>
        <div class="mt-2 grid grid-cols-3 gap-2">
          <button
            :for={i <- @instruments}
            type="button"
            phx-click="pick_instrument"
            phx-value-slug={i.slug}
            aria-pressed={@instrument_slug == i.slug}
            class={[
              "cursor-pointer rounded-lg border px-4 py-3 text-center shadow-sm transition-colors active:scale-[.98]",
              (@instrument_slug == i.slug &&
                 "border-indigo-600 bg-indigo-600 text-white shadow-md dark:border-indigo-400 dark:bg-indigo-500") ||
                "border-indigo-200 bg-indigo-50 text-indigo-800 hover:border-indigo-600 hover:bg-indigo-600 hover:text-white dark:border-indigo-800 dark:bg-indigo-950 dark:text-indigo-200 dark:hover:bg-indigo-500 dark:hover:text-white"
            ]}
          >
            {i.name}
          </button>
        </div>

        <p class="mt-4 text-sm font-medium text-gray-500">Length</p>
        <div class="mt-2 grid grid-cols-3 gap-2">
          <button
            :for={d <- @durations}
            type="button"
            phx-click="pick_duration"
            phx-value-minutes={d}
            aria-pressed={@duration_minutes == d}
            class={[
              "cursor-pointer rounded-lg border px-4 py-3 text-center shadow-sm transition-colors active:scale-[.98]",
              (@duration_minutes == d &&
                 "border-indigo-600 bg-indigo-600 text-white shadow-md dark:border-indigo-400 dark:bg-indigo-500") ||
                "border-indigo-200 bg-indigo-50 text-indigo-800 hover:border-indigo-600 hover:bg-indigo-600 hover:text-white dark:border-indigo-800 dark:bg-indigo-950 dark:text-indigo-200 dark:hover:bg-indigo-500 dark:hover:text-white"
            ]}
          >
            {d} min
          </button>
        </div>
      </section>

      <section :if={@step == :schedule} class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Available times</h2>
          <button
            type="button"
            phx-click="back"
            phx-value-to="lesson"
            class="cursor-pointer text-sm text-indigo-700 underline dark:text-indigo-300"
          >
            ← Back
          </button>
        </div>

        <p :if={@slots_error} class="mt-4 text-sm text-red-600">
          Couldn't load times. Please try again.
        </p>

        <form
          phx-change="set_cadence"
          class="mt-3 flex flex-col gap-2 text-sm sm:flex-row sm:flex-wrap sm:gap-4"
        >
          <label class="flex items-center gap-1">
            <input type="radio" name="cadence" value="once" checked={@cadence == "once"} /> Just once
          </label>
          <label class="flex items-center gap-1">
            <input type="radio" name="cadence" value="weekly" checked={@cadence == "weekly"} />
            Weekly (school year)
          </label>
          <label class="flex items-center gap-1">
            <input type="radio" name="cadence" value="biweekly" checked={@cadence == "biweekly"} />
            Every other week
          </label>
        </form>

        <p :if={!@slots_error and @slots == []} class="mt-4 text-sm text-gray-500">
          No open times in the next couple of months. Please check back soon.
        </p>

        <%!-- SINGLE: a month calendar grid — pick a day, then a time. --%>
        <div :if={@cadence == "once" and @cal_month} class="mt-4">
          <div class="flex items-center justify-between">
            <button
              type="button"
              phx-click="prev_month"
              disabled={!prev_month?(@cal_month)}
              class="cursor-pointer rounded px-2 py-1 text-indigo-700 disabled:cursor-not-allowed disabled:text-gray-300 dark:text-indigo-300"
              aria-label="Previous month"
            >
              ◀
            </button>
            <span class="font-medium">{Calendar.strftime(@cal_month, "%B %Y")}</span>
            <button
              type="button"
              phx-click="next_month"
              disabled={!next_month?(@cal_month)}
              class="cursor-pointer rounded px-2 py-1 text-indigo-700 disabled:cursor-not-allowed disabled:text-gray-300 dark:text-indigo-300"
              aria-label="Next month"
            >
              ▶
            </button>
          </div>

          <div class="mt-3 grid grid-cols-7 gap-1 text-center text-xs text-gray-500">
            <div :for={label <- ~w(Su Mo Tu We Th Fr Sa)}>{label}</div>
          </div>

          <div
            :for={week <- calendar_weeks(@cal_month)}
            class="grid grid-cols-7 gap-1 text-center text-sm"
          >
            <div :for={day <- week} class="py-0.5">
              <button
                :if={day_available?(day, @cal_month, @slots_by_day)}
                type="button"
                phx-click="pick_day"
                phx-value-date={Date.to_iso8601(day)}
                class={[
                  "w-full cursor-pointer rounded py-1 transition-colors",
                  (@selected_day == day && "bg-indigo-600 text-white dark:bg-indigo-500") ||
                    "font-semibold text-indigo-700 hover:bg-indigo-50 dark:text-indigo-300 dark:hover:bg-indigo-900"
                ]}
              >
                {day.day}
              </button>
              <span
                :if={!day_available?(day, @cal_month, @slots_by_day)}
                class={[
                  "block py-1",
                  (day.month == @cal_month.month && "text-gray-400") || "text-gray-300"
                ]}
              >
                {day.day}
              </span>
            </div>
          </div>

          <div :if={@selected_day} class="mt-5">
            <h3 class="text-sm font-medium">{Calendar.strftime(@selected_day, "%A, %b %-d")}</h3>
            <div class="mt-2 grid grid-cols-3 gap-2 sm:grid-cols-5">
              <button
                :for={slot <- day_slots(@selected_day, @slots_by_day)}
                type="button"
                phx-click="pick_slot"
                phx-value-start={DateTime.to_iso8601(slot.starts_at)}
                class="cursor-pointer rounded border border-indigo-200 bg-indigo-50 px-2 py-2 text-center text-sm tabular-nums text-indigo-800 shadow-sm transition-colors hover:border-indigo-600 hover:bg-indigo-600 hover:text-white active:scale-[.98] dark:border-indigo-800 dark:bg-indigo-950 dark:text-indigo-200 dark:hover:bg-indigo-500 dark:hover:text-white sm:py-1"
              >
                {time_label(slot.starts_at)}
              </button>
            </div>
          </div>
        </div>

        <%!-- RECURRING, step 1: pick the usual weekday + time (a full representative week). --%>
        <div :if={@cadence != "once"} class="mt-4">
          <p class="text-sm text-gray-600">
            Pick your usual day &amp; time — repeats {cadence_word(@cadence)} through June 30.
            Pause or cancel anytime; billed monthly.
          </p>

          <div class="mt-3 space-y-3">
            <div
              :for={day <- representative_week()}
              class="flex flex-col gap-1.5 border-b border-gray-100 pb-3 last:border-0 last:pb-0 sm:flex-row sm:items-start sm:gap-3 sm:border-0 sm:pb-0"
            >
              <span class="text-sm font-semibold text-gray-800 sm:w-24 sm:shrink-0 sm:pt-1.5 sm:font-medium sm:text-gray-700">
                {Calendar.strftime(day, "%A")}
              </span>
              <div class="grid flex-1 grid-cols-3 gap-2 sm:grid-cols-6">
                <button
                  :for={slot <- day_slots(day, @slots_by_day)}
                  type="button"
                  phx-click="pick_pattern"
                  phx-value-start={DateTime.to_iso8601(slot.starts_at)}
                  class={[
                    "cursor-pointer rounded border px-2 py-2 text-center text-sm tabular-nums shadow-sm transition-colors active:scale-[.98] sm:py-1",
                    (pattern_selected?(@rec_pattern, slot.starts_at) &&
                       "border-indigo-600 bg-indigo-600 text-white shadow-md dark:border-indigo-400 dark:bg-indigo-500") ||
                      "border-indigo-200 bg-indigo-50 text-indigo-800 hover:border-indigo-600 hover:bg-indigo-600 hover:text-white dark:border-indigo-800 dark:bg-indigo-950 dark:text-indigo-200 dark:hover:bg-indigo-500 dark:hover:text-white"
                  ]}
                >
                  {time_label(slot.starts_at)}
                </button>
                <span :if={day_slots(day, @slots_by_day) == []} class="pt-1.5 text-sm text-gray-300">—</span>
              </div>
            </div>
          </div>

          <%!-- RECURRING, step 2: choose the start date, then continue. --%>
          <div :if={@rec_pattern} class="mt-5 rounded-lg border border-indigo-200 bg-indigo-50/50 p-4">
            <div class="flex items-center gap-3 text-sm">
              <span class="font-medium">Starts on</span>
              <button
                type="button"
                phx-click="start_earlier"
                disabled={!can_start_earlier?(@series_start, @rec_pattern)}
                class="cursor-pointer rounded px-2 py-1 text-indigo-700 disabled:cursor-not-allowed disabled:text-gray-300 dark:text-indigo-300"
                aria-label="Earlier start"
              >
                ◀
              </button>
              <span class="font-medium tabular-nums">{Calendar.strftime(@series_start, "%A, %b %-d")}</span>
              <button
                type="button"
                phx-click="start_later"
                disabled={!can_start_later?(@series_start, @rec_pattern)}
                class="cursor-pointer rounded px-2 py-1 text-indigo-700 disabled:cursor-not-allowed disabled:text-gray-300 dark:text-indigo-300"
                aria-label="Later start"
              >
                ▶
              </button>
            </div>

            <p class="mt-3 text-sm text-indigo-900">
              Every {Calendar.strftime(@series_start, "%A")}, {time_label(@rec_pattern)}
              <span :if={@series_preview}>
                · {length(@series_preview.bookable)} lessons through Jun 30<span :if={
                  @series_preview.conflicted != []
                }>· {length(@series_preview.conflicted)} week(s) need another time</span>
              </span>
            </p>

            <button
              type="button"
              phx-click="to_details"
              class="mt-3 w-full cursor-pointer rounded-lg bg-indigo-600 px-4 py-2.5 font-medium text-white shadow-sm transition-colors hover:bg-indigo-700 active:scale-[.98] dark:bg-indigo-500 dark:hover:bg-indigo-400 sm:w-auto"
            >
              Continue
            </button>
          </div>
        </div>
      </section>

      <section :if={@step == :details} class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Your details</h2>
          <button
            type="button"
            phx-click="back"
            phx-value-to="schedule"
            class="cursor-pointer text-sm text-indigo-700 underline dark:text-indigo-300"
          >
            ← Back
          </button>
        </div>

        <p class="mt-2 text-sm text-gray-500">
          {slot_label(@selected_slot)} · {@duration_minutes} min
        </p>

        <p :if={@series_preview} class="mt-2 text-sm text-indigo-700">
          {length(@series_preview.bookable)} lessons through June 30<span :if={
            @series_preview.conflicted != []
          }>
            · {length(@series_preview.conflicted)} weeks need another time
          </span>
        </p>

        <.form for={@form} phx-change="validate_details" phx-submit="book" class="mt-4 space-y-3">
          <.input field={@form[:name]} label="Your name" required />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:phone]} label="Phone (optional)" />
          <button
            type="submit"
            class="cursor-pointer rounded-lg bg-indigo-600 px-4 py-2.5 font-medium text-white shadow-sm transition-colors hover:bg-indigo-700 active:scale-[.98] dark:bg-indigo-500 dark:hover:bg-indigo-400"
          >
            Confirm booking
          </button>
        </.form>
      </section>

      <section :if={@step == :done} class="mt-6 rounded border p-4">
        <p :if={@booked_series} class="font-medium">
          Your series is booked — {@booked_series.count} lessons through June 30! Check your email
          for the schedule and calendar invites.
        </p>
        <p :if={@booked_series && @booked_series.conflicted != []} class="mt-2 text-sm text-gray-600">
          {length(@booked_series.conflicted)} week(s) couldn't use your usual time — we'll follow up
          about alternates.
        </p>
        <p :if={!@booked_series} class="font-medium">
          You're booked! Check your email for a confirmation and calendar invite.
        </p>
      </section>
    </div>
    """
  end

  ## Helpers

  defp step_index(step), do: Enum.find_index(@steps, fn {key, _} -> key == step end)

  # A step is "done" (shows a check) once the current step is past it.
  defp done?(current, key), do: step_index(current) > step_index(key)

  defp step_status(current, key) do
    cond do
      current == key -> "is-current"
      done?(current, key) -> "is-done"
      true -> "is-todo"
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp parse_duration(""), do: nil
  defp parse_duration(v), do: String.to_integer(v)

  defp studio_tz, do: Application.get_env(:music_studio, MusicStudio.Scheduling)[:studio_timezone]

  defp today_local,
    do: DateTime.utc_now() |> DateTime.shift_zone!(studio_tz()) |> DateTime.to_date()

  # Advance to the schedule step once both instrument and duration are chosen.
  defp maybe_advance(socket) do
    if socket.assigns.instrument_slug && socket.assigns.duration_minutes,
      do: load_and_schedule(socket),
      else: socket
  end

  defp load_and_schedule(socket) do
    today = today_local()

    {:ok, slots} =
      Scheduling.list_available_slots(%{
        instrument_slug: socket.assigns.instrument_slug,
        duration_minutes: socket.assigns.duration_minutes,
        from: today,
        # Single bookings only look two months out — nobody books further than that.
        to: Date.add(today, 62)
      })

    by_day = slots_by_day(slots)

    assign(socket,
      slots: slots,
      slots_by_day: by_day,
      cal_month: earliest_month(by_day, today),
      slots_error: nil,
      selected_slot: nil,
      selected_day: nil,
      step: :schedule
    )
  end

  defp local_date(dt), do: dt |> DateTime.shift_zone!(studio_tz()) |> DateTime.to_date()

  # %{Date => [slot, ...]} keyed by the slot's start date in studio time (slots arrive sorted).
  defp slots_by_day(slots), do: Enum.group_by(slots, &local_date(&1.starts_at))

  defp day_slots(day, by_day), do: Map.get(by_day, day, [])

  defp day_available?(day, cal_month, by_day),
    do: day.month == cal_month.month and day_slots(day, by_day) != []

  defp earliest_month(by_day, today) do
    case Map.keys(by_day) do
      [] -> Date.beginning_of_month(today)
      days -> days |> Enum.min(Date) |> Date.beginning_of_month()
    end
  end

  # Sunday-first weeks covering the whole displayed month (with adjacent-month padding days).
  defp calendar_weeks(month) do
    first = Date.beginning_of_month(month)
    last = Date.end_of_month(month)
    grid_start = Date.add(first, -(Date.day_of_week(first, :sunday) - 1))
    grid_end = Date.add(last, 7 - Date.day_of_week(last, :sunday))
    grid_start |> Date.range(grid_end) |> Enum.chunk_every(7)
  end

  # A full upcoming week (Sun–Sat of next week) — always future, so every weekday shows
  # its real openings (empties are greyed) rather than a partial current week.
  defp representative_week do
    base = Date.add(today_local(), 7)
    start = Date.add(base, -(Date.day_of_week(base, :sunday) - 1))
    Enum.map(0..6, &Date.add(start, &1))
  end

  # Earliest bookable occurrence of `weekday` (1=Mon..7=Sun): from tomorrow (24h notice).
  defp default_start(weekday) do
    floor = Date.add(today_local(), 1)
    Date.add(floor, rem(weekday - Date.day_of_week(floor) + 7, 7))
  end

  defp put_series_slot(%{assigns: %{rec_pattern: nil}} = socket), do: socket

  defp put_series_slot(%{assigns: %{rec_pattern: dt, series_start: start}} = socket) do
    time = dt |> DateTime.shift_zone!(studio_tz()) |> DateTime.to_time()

    assign(
      socket,
      :selected_slot,
      MusicStudio.Scheduling.Recurrence.occurrence_utc(start, time, studio_tz())
    )
  end

  defp shift_start(socket, days) do
    weekday = socket.assigns.rec_pattern |> local_date() |> Date.day_of_week()
    floor = default_start(weekday)
    ceil = last_start(weekday)
    target = Date.add(socket.assigns.series_start, days)

    clamped =
      cond do
        Date.compare(target, floor) == :lt -> floor
        Date.compare(target, ceil) == :gt -> ceil
        true -> target
      end

    assign(socket, :series_start, clamped)
  end

  # The latest a series may start and still book at least one lesson: the last occurrence
  # of the pattern's weekday on or before the term end (June 30). Without this ceiling,
  # "start later" could push the start past term end, yielding a 0-lesson enrollment that
  # still holds the slot (GH #7).
  defp last_start(weekday) do
    term_end = MusicStudio.Scheduling.Recurrence.term_end(default_start(weekday))
    Date.add(term_end, -rem(Date.day_of_week(term_end) - weekday + 7, 7))
  end

  defp can_start_earlier?(nil, _rec_pattern), do: false

  defp can_start_earlier?(series_start, rec_pattern) do
    weekday = rec_pattern |> local_date() |> Date.day_of_week()
    Date.compare(series_start, default_start(weekday)) == :gt
  end

  defp can_start_later?(nil, _rec_pattern), do: false

  defp can_start_later?(series_start, rec_pattern) do
    weekday = rec_pattern |> local_date() |> Date.day_of_week()
    Date.compare(series_start, last_start(weekday)) == :lt
  end

  defp pattern_selected?(nil, _starts_at), do: false
  defp pattern_selected?(rec, starts_at), do: DateTime.compare(rec, starts_at) == :eq

  defp min_month, do: Date.beginning_of_month(today_local())
  defp max_month, do: Date.beginning_of_month(Date.add(today_local(), 62))
  defp prev_month?(cal), do: Date.compare(cal, min_month()) == :gt
  defp next_month?(cal), do: Date.compare(cal, max_month()) == :lt

  defp shift_month(socket, n) do
    cal = socket.assigns.cal_month || min_month()
    idx = cal.year * 12 + (cal.month - 1) + n
    target = Date.new!(div(idx, 12), rem(idx, 12) + 1, 1)

    clamped =
      cond do
        Date.compare(target, min_month()) == :lt -> min_month()
        Date.compare(target, max_month()) == :gt -> max_month()
        true -> target
      end

    assign(socket, cal_month: clamped, selected_day: nil)
  end

  defp cadence_word("biweekly"), do: "every other week"
  defp cadence_word(_), do: "every week"

  defp time_label(dt),
    do: dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%-I:%M %p")

  defp slot_label(dt) do
    dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%a %b %-d, %-I:%M %p")
  end
end
