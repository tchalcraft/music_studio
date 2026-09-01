defmodule MusicStudioWeb.BookingManageLive do
  @moduledoc "Self-service manage view: cancel (v1) a booking via its token."
  use MusicStudioWeb, :live_view

  alias MusicStudio.Scheduling

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Manage booking")
     |> assign(:token, token)
     |> assign(:lesson, Scheduling.get_lesson_by_token(token))
     |> assign(:cancelled, false)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    case Scheduling.cancel_booking(socket.assigns.token) do
      {:ok, _} -> {:noreply, assign(socket, cancelled: true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not cancel.")}
    end
  end

  @impl true
  def render(assigns) do
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
