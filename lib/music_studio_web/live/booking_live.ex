defmodule MusicStudioWeb.BookingLive do
  @moduledoc "Public booking flow: pick instrument + duration → slot → details → instant book."
  use MusicStudioWeb, :live_view

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling

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
     |> assign(:instruments, Catalog.list_instruments())
     |> assign(:durations, durations)
     |> assign(:instrument_slug, nil)
     |> assign(:duration_minutes, nil)
     |> assign(:slots, [])
     |> assign(:slots_error, nil)
     |> assign(:selected_slot, nil)
     |> assign(:booked, nil)
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
      {:ok, slots} -> {:noreply, assign(socket, slots: slots, slots_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, slots: [], slots_error: inspect(reason))}
    end
  end

  def handle_event("choose", _params, socket) do
    {:noreply, assign(socket, slots: [], selected_slot: nil)}
  end

  def handle_event("pick_slot", %{"start" => iso}, socket) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    {:noreply, assign(socket, :selected_slot, dt)}
  end

  def handle_event("book", %{"booking" => params}, socket) do
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
        {:noreply, assign(socket, booked: lesson, slots: [], selected_slot: nil)}

      {:error, :slot_taken} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry — that time was just taken. Please pick another.")
         |> assign(selected_slot: nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  defp studio_tz, do: Application.get_env(:music_studio, MusicStudio.Scheduling)[:studio_timezone]

  defp slot_label(dt) do
    dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%a %b %-d, %-I:%M %p")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl p-6">
      <h1 class="text-2xl font-semibold">Book a lesson</h1>

      <div :if={@booked} class="mt-6 rounded border p-4">
        <p class="font-medium">
          You're booked! Check your email for a confirmation and calendar invite.
        </p>
      </div>

      <form :if={!@booked} id="booking-picker" phx-change="choose" class="mt-6 flex gap-4">
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

      <p :if={@slots_error} class="mt-4 text-sm text-red-600">
        Couldn't load times. Please try again.
      </p>

      <div :if={!@booked and @slots != []} class="mt-6">
        <h2 class="font-medium">Available times</h2>
        <div class="mt-2 flex flex-wrap gap-2">
          <button
            :for={slot <- @slots}
            type="button"
            phx-click="pick_slot"
            phx-value-start={DateTime.to_iso8601(slot.starts_at)}
            class={[
              "rounded border px-3 py-1",
              @selected_slot == slot.starts_at && "bg-indigo-600 text-white"
            ]}
          >
            {slot_label(slot.starts_at)}
          </button>
        </div>
      </div>

      <.form :if={!@booked and @selected_slot} for={@form} phx-submit="book" class="mt-6 space-y-3">
        <.input field={@form[:name]} label="Your name" required />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:phone]} label="Phone (optional)" />
        <button type="submit" class="rounded bg-indigo-600 px-4 py-2 text-white">
          Confirm booking
        </button>
      </.form>
    </div>
    """
  end
end
