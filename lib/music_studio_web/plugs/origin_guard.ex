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
  """
  @behaviour Plug

  import Plug.Conn

  @header "x-origin-auth"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Application.get_env(:music_studio, :origin_auth_secret) do
      secret when is_binary(secret) and secret != "" -> verify(conn, secret)
      _ -> conn
    end
  end

  defp verify(conn, secret) do
    with [given] <- get_req_header(conn, @header),
         true <- Plug.Crypto.secure_compare(given, secret) do
      delete_req_header(conn, @header)
    else
      _ -> conn |> send_resp(403, "Forbidden") |> halt()
    end
  end
end
