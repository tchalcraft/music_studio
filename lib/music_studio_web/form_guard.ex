defmodule MusicStudioWeb.FormGuard do
  @moduledoc """
  Abuse protection for the public forms (inquiry, booking): a per-IP rate limit plus a
  Cloudflare Turnstile bot check, applied by `check/3` before anything is saved or emailed.

  The booking confirmation email goes to whatever address the visitor types, so an
  unthrottled form is a spam relay from our domain and a way to block real lesson slots.

  Usage in a LiveView:

      on_mount MusicStudioWeb.FormGuard          # assigns :client_ip
      <.turnstile id="inquiry-turnstile" />      # inside the <.form>
      case FormGuard.check(socket, :inquiry, params) do
        :ok -> …
        {:error, message, socket} -> {:noreply, put_flash(socket, :error, message)}
      end
  """
  use Phoenix.Component

  alias MusicStudio.{RateLimit, Turnstile}

  # {limit, window} per client IP, per form.
  @limits %{inquiry: {5, :timer.hours(1)}, booking: {5, :timer.hours(1)}}
  @token_param "cf-turnstile-response"

  @doc """
  `on_mount` hook: records the visitor's IP. Behind Cloudflare the TCP peer is a Cloudflare
  edge, so prefer `cf-connecting-ip`. It can be trusted because OriginGuard rejects connected
  mounts that didn't come through Cloudflare.
  """
  def on_mount(:default, _params, _session, socket) do
    {:cont, assign(socket, :client_ip, client_ip(socket))}
  end

  @doc """
  Runs the rate limit, then the Turnstile check. On failure returns a visitor-facing
  message and a socket that resets the widget (tokens are single-use).
  """
  def check(socket, form, params) when is_map_key(@limits, form) do
    {limit, window} = @limits[form]
    ip = socket.assigns[:client_ip]

    cond do
      not RateLimit.allow?("#{form}:#{ip || "unknown"}", window, limit) ->
        {:error, "Too many attempts from your connection. Please try again in a little while.",
         reset_widget(socket)}

      Turnstile.verify(params[@token_param], ip) != :ok ->
        {:error, "Please complete the quick security check and try again.", reset_widget(socket)}

      true ->
        :ok
    end
  end

  @doc "Push a widget reset after a submit so the next attempt gets a fresh token."
  def reset_widget(socket), do: Phoenix.LiveView.push_event(socket, "turnstile:reset", %{})

  attr :id, :string, required: true

  @doc """
  The Turnstile widget (JS: `assets/js/turnstile_hook.js`). Renders nothing when Turnstile
  isn't configured (dev/test).
  """
  def turnstile(assigns) do
    assigns = assign(assigns, :site_key, Turnstile.site_key())

    ~H"""
    <div :if={@site_key} id={@id} phx-hook="Turnstile" phx-update="ignore" data-sitekey={@site_key}>
    </div>
    """
  end

  defp client_ip(socket) do
    if Phoenix.LiveView.connected?(socket) do
      headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

      :proplists.get_value("cf-connecting-ip", headers, nil) ||
        peer_ip(Phoenix.LiveView.get_connect_info(socket, :peer_data))
    end
  end

  defp peer_ip(%{address: address}), do: address |> :inet.ntoa() |> to_string()
  defp peer_ip(_), do: nil
end
