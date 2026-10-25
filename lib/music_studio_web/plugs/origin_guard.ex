defmodule MusicStudioWeb.Plugs.OriginGuard do
  @moduledoc """
  Rejects requests that didn't come through Cloudflare.

  Cloudflare's late-transform rule adds `x-origin-auth: <secret>` to every request it
  forwards. Anything hitting the raw `*.onrender.com` host directly (bypassing the WAF,
  rate limits, and Access) lacks it and gets a bare 403.

  Enforced only when `config :music_studio, :origin_auth_secret` is set (prod:
  `ORIGIN_AUTH_SECRET`). Unset means pass-through, so the code can ship before DNS has
  moved to Cloudflare. `/up` is answered earlier by `MusicStudioWeb.Plugs.Health`, so
  Render's direct health probes never reach this plug.

  Phoenix dispatches the `/live` socket *before* the plug pipeline, so a WebSocket opened
  straight at the origin never passes through `call/2`. `on_mount/4` closes that gap: the
  endpoint passes `:x_headers` as connect info, and every connected LiveView mount checks
  the same secret.
  """
  @behaviour Plug

  import Plug.Conn

  @header "x-origin-auth"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case secret() do
      nil -> conn
      secret -> verify(conn, secret)
    end
  end

  @doc "LiveView `on_mount` hook: connected mounts must carry the Cloudflare secret too."
  def on_mount(:default, _params, _session, socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         secret when is_binary(secret) <- secret() do
      headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

      if valid?(:proplists.get_value(@header, headers, nil), secret),
        do: {:cont, socket},
        else: {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    else
      _ -> {:cont, socket}
    end
  end

  defp secret do
    case Application.get_env(:music_studio, :origin_auth_secret) do
      secret when is_binary(secret) and secret != "" -> secret
      _ -> nil
    end
  end

  defp valid?(given, secret) when is_binary(given), do: Plug.Crypto.secure_compare(given, secret)
  defp valid?(_given, _secret), do: false

  defp verify(conn, secret) do
    with [given] <- get_req_header(conn, @header),
         true <- valid?(given, secret) do
      conn
    else
      _ -> conn |> send_resp(403, "Forbidden") |> halt()
    end
  end
end
