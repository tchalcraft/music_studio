defmodule MusicStudioWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP basic auth gate for the Beacon LiveAdmin at `/cms`.

  The admin can edit event/info handlers and live data, which Beacon compiles into running
  code, so an open `/cms` is remote code execution. Credentials come from
  `config :music_studio, :admin_auth, username: …, password: …` (prod: `ADMIN_USER` /
  `ADMIN_PASSWORD`). If either is missing the gate **fails closed** and rejects everyone.

  On success it marks the session (`"admin_authenticated"`) so the LiveAdmin `on_mount/4`
  hook can refuse LiveView joins that didn't come through this plug.
  """
  @behaviour Plug

  import Plug.Conn

  @session_key "admin_authenticated"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, username, password} <- credentials(),
         {given_user, given_pass} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- Plug.Crypto.secure_compare(given_user, username),
         true <- Plug.Crypto.secure_compare(given_pass, password) do
      put_session(conn, @session_key, true)
    else
      _ ->
        conn
        |> delete_session(@session_key)
        |> Plug.BasicAuth.request_basic_auth(realm: "Studio admin")
        |> halt()
    end
  end

  @doc "LiveView `on_mount` hook: only sessions marked by `call/2` may mount the admin."
  def on_mount(:require_admin, _params, session, socket) do
    if session[@session_key] == true do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp credentials do
    config = Application.get_env(:music_studio, :admin_auth, [])

    case {config[:username], config[:password]} do
      {user, pass} when is_binary(user) and user != "" and is_binary(pass) and pass != "" ->
        {:ok, user, pass}

      _ ->
        :error
    end
  end
end
