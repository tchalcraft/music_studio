defmodule MusicStudioWeb.Plugs.ScannerBlock do
  @moduledoc """
  Answers vulnerability-scanner probes (`/wp-admin/…`, `*.php`, `/.env`, …) with a bare
  404 before they reach the router.

  Without this, those paths fall through to the Beacon catch-all. This site has no PHP,
  WordPress or dotfiles, so none of these paths can be legitimate. Cloudflare blocks the
  same patterns at the edge; this is the origin-side backstop.
  """
  @behaviour Plug

  import Plug.Conn

  @prefixes ~w(/wp- /wordpress /.env /.git /.aws /.ssh /_next /xmlrpc /cgi-bin /vendor /phpmyadmin /pma)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    if scanner_path?(path) do
      conn |> send_resp(404, "Not Found") |> halt()
    else
      conn
    end
  end

  @doc false
  def scanner_path?(path) do
    down = String.downcase(path)

    String.ends_with?(down, ".php") or String.contains?(down, ".php/") or
      Enum.any?(@prefixes, &String.starts_with?(down, &1))
  end
end
