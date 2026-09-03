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
     |> assign(:slots_error, nil)
     |> assign(:selected_slot, nil)
     |> assign(:cadence, "once")
     |> assign(:series_preview, nil)
     |> assign(:booked, nil)
     |> assign(:booked_series, nil)
     |> assign(:form, to_form(%{"name" => "", "email" => "", "phone" => ""}, as: :booking))}
  end

  @impl true
  def handle_event("choose", %{"instrument_slug" => slug, "duration_minutes" => dur}, socket)
      when slug != "" and dur != "" do
    duration = String.to_integer(dur)
    today = DateTime.utc_now() |> DateTime.shift_zone!(studio_tz()) |> DateTime.to_date()

    socket = assign(socket, instrument_slug: slug, duration_minutes: duration, selected_slot: nil)

    case Scheduling.list_available_slots(%{
           instrument_slug: slug,
           duration_minutes: duration,
           from: today,
           to: Date.add(today, 28)
         }) do
      {:ok, slots} ->
        {:noreply, assign(socket, slots: slots, slots_error: nil, step: :schedule)}

      {:error, reason} ->
        {:noreply, assign(socket, slots: [], slots_error: inspect(reason), step: :schedule)}
    end
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

  def handle_event("set_cadence", %{"cadence" => cadence}, socket) do
    {:noreply, socket |> assign(:cadence, cadence) |> maybe_preview()}
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
        <form id="booking-picker" phx-change="choose" class="mt-3 flex gap-4">
          <select name="instrument_slug" class="rounded border p-2">
            <option value="">Instrument…</option>
            <option :for={i <- @instruments} value={i.slug} selected={i.slug == @instrument_slug}>
              {i.name}
            </option>
          </select>
          <select name="duration_minutes" class="rounded border p-2">
            <option value="">Length…</option>
            <option :for={d <- @durations} value={d} selected={d == @duration_minutes}>
              {d} min
            </option>
          </select>
        </form>
      </section>

      <section :if={@step == :schedule} class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Available times</h2>
          <button
            type="button"
            phx-click="back"
            phx-value-to="lesson"
            class="text-sm text-indigo-700 underline"
          >
            ← Back
          </button>
        </div>

        <p :if={@slots_error} class="mt-4 text-sm text-red-600">
          Couldn't load times. Please try again.
        </p>

        <form phx-change="set_cadence" class="mt-3 flex flex-wrap gap-4 text-sm">
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
          No open times in the next few weeks. Please check back soon.
        </p>

        <div class="mt-3 flex flex-wrap gap-2">
          <button
            :for={slot <- @slots}
            type="button"
            phx-click="pick_slot"
            phx-value-start={DateTime.to_iso8601(slot.starts_at)}
            class="rounded border px-3 py-1 hover:border-indigo-600"
          >
            {slot_label(slot.starts_at)}
          </button>
        </div>
      </section>

      <section :if={@step == :details} class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Your details</h2>
          <button
            type="button"
            phx-click="back"
            phx-value-to="schedule"
            class="text-sm text-indigo-700 underline"
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
          <button type="submit" class="rounded bg-indigo-600 px-4 py-2 text-white">
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

  defp slot_label(dt) do
    dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%a %b %-d, %-I:%M %p")
  end
end
