defmodule MusicStudioWeb.CacheBodyReader do
  @moduledoc """
  A `Plug.Parsers` body reader that caches the raw request body for the Stripe webhook path.

  Stripe webhook signatures are computed over the exact request bytes, but `Plug.Parsers`
  consumes the body while decoding JSON. We stash the raw body in `conn.assigns.raw_body`
  (only for `/webhooks/stripe`, to avoid buffering every request) so the controller can
  verify the signature against the original payload.
  """
  @webhook_path "/webhooks/stripe"

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    conn =
      if conn.request_path == @webhook_path do
        update_in(conn.assigns[:raw_body], &[body | &1 || []])
      else
        conn
      end

    {:ok, body, conn}
  end
end
