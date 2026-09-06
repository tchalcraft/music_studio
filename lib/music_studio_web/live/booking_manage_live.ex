defmodule MusicStudioWeb.BookingManageLive do
  @moduledoc """
  Self-service manage view. A token resolves to either a recurring **series** (enrollment)
  — with per-week skip, a month-long pause, and cancel-series — or a **single lesson** with
  a simple cancel.
  """
  use MusicStudioWeb, :live_view

  alias MusicStudio.Scheduling

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Scheduling.get_series_by_token(token) do
      nil -> {:ok, mount_single(token, socket)}
      series -> {:ok, mount_series(series, socket)}
    end
  end

  defp mount_series(series, socket) do
    socket
    |> assign(:page_title, "Manage your series")
    |> assign(:kind, :series)
    |> assign(:series, series)
    |> assign(:lessons, Scheduling.list_series_lessons(series))
    |> assign(:cancelled, false)
  end

  defp mount_single(token, socket) do
    socket
    |> assign(:page_title, "Manage booking")
    |> assign(:kind, :single)
    |> assign(:token, token)
    |> assign(:lesson, Scheduling.get_lesson_by_token(token))
    |> assign(:cancelled, false)
    |> assign(:rescheduling, false)
    |> assign(:rescheduled, false)
    |> assign(:slots_by_day, %{})
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    case Scheduling.cancel_booking(socket.assigns.token) do
      {:ok, _} -> {:noreply, assign(socket, cancelled: true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not cancel.")}
    end
  end

  def handle_event("start_reschedule", _params, socket) do
    {:noreply,
     socket
     |> assign(:rescheduling, true)
     |> assign(:slots_by_day, reschedule_slots(socket.assigns.lesson))}
  end

  def handle_event("cancel_reschedule", _params, socket) do
    {:noreply, assign(socket, rescheduling: false, slots_by_day: %{})}
  end

  def handle_event("pick_new_slot", %{"start" => iso}, socket) do
    {:ok, new_starts_at, _} = DateTime.from_iso8601(iso)

    case Scheduling.reschedule_booking(socket.assigns.token, new_starts_at) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:rescheduling, false)
         |> assign(:rescheduled, true)
         |> assign(:lesson, Scheduling.get_lesson_by_token(socket.assigns.token))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That time isn't available — please pick another.")}
    end
  end

  def handle_event("skip", %{"token" => lesson_token}, socket) do
    case Scheduling.skip_occurrence(lesson_token) do
      {:ok, _} -> {:noreply, refresh_lessons(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not skip that lesson.")}
    end
  end

  def handle_event("pause", _params, socket) do
    case socket.assigns.lessons do
      [] ->
        {:noreply, socket}

      [next | _] ->
        from = DateTime.to_date(next.scheduled_start)
        {:ok, _} = Scheduling.pause_series(socket.assigns.series.booking_token, from)
        {:noreply, refresh_lessons(socket)}
    end
  end

  def handle_event("cancel_series", _params, socket) do
    case Scheduling.cancel_series(socket.assigns.series.booking_token) do
      {:ok, _} -> {:noreply, socket |> assign(:cancelled, true) |> assign(:lessons, [])}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not cancel the series.")}
    end
  end

  defp refresh_lessons(socket) do
    assign(socket, :lessons, Scheduling.list_series_lessons(socket.assigns.series))
  end

  # Available slots for this lesson's instrument+duration over the next ~3 weeks, grouped by
  # studio-local day (reuses the same availability engine as /book).
  defp reschedule_slots(%{instrument: %{slug: slug}, duration_minutes: duration}) do
    from = Date.add(Date.utc_today(), 1)
    to = Date.add(Date.utc_today(), 21)

    case Scheduling.list_available_slots(%{
           instrument_slug: slug,
           duration_minutes: duration,
           from: from,
           to: to
         }) do
      {:ok, slots} ->
        Enum.group_by(slots, &DateTime.to_date(DateTime.shift_zone!(&1.starts_at, studio_tz())))

      _ ->
        %{}
    end
  end

  defp reschedule_slots(_lesson), do: %{}

  defp studio_tz, do: Application.get_env(:music_studio, MusicStudio.Scheduling)[:studio_timezone]

  defp lesson_label(dt) do
    dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%a %b %-d, %Y · %-I:%M %p")
  end

  @impl true
  def render(%{kind: :series} = assigns) do
    ~H"""
    <div class="mx-auto max-w-xl p-6">
      <h1 class="text-2xl font-semibold">Your lesson series</h1>
      <p :if={@cancelled} class="mt-4">Your series has been cancelled.</p>

      <div :if={!@cancelled}>
        <p class="mt-2 text-sm text-gray-600">
          Upcoming lessons — skip one, pause for up to a month (your time stays held), or cancel the series.
        </p>

        <ul class="mt-4 divide-y rounded border">
          <li :for={lesson <- @lessons} class="flex items-center justify-between p-3">
            <span>{lesson_label(lesson.scheduled_start)}</span>
            <button
              type="button"
              phx-click="skip"
              phx-value-token={lesson.booking_token}
              data-confirm="Skip this week? Your time stays reserved."
              class="text-sm text-indigo-700 underline"
            >
              Skip
            </button>
          </li>
        </ul>

        <p :if={@lessons == []} class="mt-4 text-sm text-gray-500">No upcoming lessons.</p>

        <div class="mt-6 flex gap-3">
          <button
            :if={@lessons != []}
            type="button"
            phx-click="pause"
            data-confirm="Pause the next few weeks? Your time stays reserved."
            class="rounded border px-4 py-2"
          >
            Pause (up to a month)
          </button>
          <button
            type="button"
            phx-click="cancel_series"
            data-confirm="Cancel the whole series?"
            class="rounded bg-red-600 px-4 py-2 text-white"
          >
            Cancel series
          </button>
        </div>
      </div>
    </div>
    """
  end

  def render(%{kind: :single} = assigns) do
    ~H"""
    <div class="mx-auto max-w-xl p-6">
      <h1 class="text-2xl font-semibold">Manage your booking</h1>
      <p :if={!@lesson} class="mt-4">Booking not found.</p>
      <p :if={@cancelled} class="mt-4">Your booking has been cancelled.</p>
      <p :if={@rescheduled} class="mt-4">
        Your lesson has been moved to <strong>{lesson_label(@lesson.scheduled_start)}</strong>.
        We've emailed you the new details.
      </p>

      <div :if={@lesson && !@cancelled && !@rescheduled}>
        <p class="mt-2 text-sm text-gray-600">
          Your lesson is on <strong>{lesson_label(@lesson.scheduled_start)}</strong>.
        </p>

        <div :if={!@rescheduling} class="mt-6 flex gap-3">
          <button
            type="button"
            phx-click="start_reschedule"
            class="cursor-pointer rounded border px-4 py-2 text-indigo-700"
          >
            Pick a new time
          </button>
          <button
            type="button"
            phx-click="cancel"
            data-confirm="Cancel this lesson?"
            class="cursor-pointer rounded bg-red-600 px-4 py-2 text-white"
          >
            Cancel booking
          </button>
        </div>

        <div :if={@rescheduling} class="mt-6">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-medium">Choose a new time</h2>
            <button
              type="button"
              phx-click="cancel_reschedule"
              class="cursor-pointer text-sm text-gray-500 underline"
            >
              Back
            </button>
          </div>

          <p :if={@slots_by_day == %{}} class="mt-4 text-sm text-gray-500">
            No open times in the next few weeks. Please cancel and book again, or contact the studio.
          </p>

          <div :for={day <- Enum.sort(Map.keys(@slots_by_day))} class="mt-4">
            <div class="text-sm font-medium text-gray-700">{day_label(day)}</div>
            <div class="mt-1 flex flex-wrap gap-2">
              <button
                :for={slot <- Enum.sort_by(@slots_by_day[day], & &1.starts_at, DateTime)}
                type="button"
                phx-click="pick_new_slot"
                phx-value-start={DateTime.to_iso8601(slot.starts_at)}
                class="cursor-pointer rounded border px-3 py-1.5 text-sm text-indigo-700 hover:bg-indigo-50"
              >
                {time_label(slot.starts_at)}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp day_label(%Date{} = date), do: Calendar.strftime(date, "%A, %B %-d")

  defp time_label(dt) do
    dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%-I:%M %p")
  end
end
