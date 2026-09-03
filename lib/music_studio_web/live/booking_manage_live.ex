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
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    case Scheduling.cancel_booking(socket.assigns.token) do
      {:ok, _} -> {:noreply, assign(socket, cancelled: true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not cancel.")}
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
      <div :if={@lesson && !@cancelled} class="mt-4">
        <button
          phx-click="cancel"
          data-confirm="Cancel this lesson?"
          class="rounded bg-red-600 px-4 py-2 text-white"
        >
          Cancel booking
        </button>
      </div>
    </div>
    """
  end
end
