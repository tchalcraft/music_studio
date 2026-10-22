defmodule MusicStudioWeb.Plugs.Health do
  @moduledoc """
  `GET /up` → `200 ok`, with no session, router, or database touch.

  Render's health check (`healthCheckPath: /up`) probes every few seconds. Mounted in the
  endpoint ahead of `Plug.Telemetry`, so the probes don't flood the logs either.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method, request_path: "/up"} = conn, _opts)
      when method in ["GET", "HEAD"] do
    conn |> put_resp_content_type("text/plain") |> send_resp(200, "ok") |> halt()
  end

  def call(conn, _opts), do: conn
end
