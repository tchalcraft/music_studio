defmodule MusicStudioWeb.GoogleOAuthController do
  @moduledoc "One-time Google Calendar connect flow, guarded by a setup token."
  use MusicStudioWeb, :controller

  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  plug :require_setup_token when action in [:connect]

  def connect(conn, _params) do
    redirect(conn, external: GoogleAuth.authorize_url("setup"))
  end

  def callback(conn, %{"code" => code}) do
    case GoogleAuth.exchange_code(code) do
      {:ok, tokens} ->
        {:ok, _} =
          Credentials.upsert(%{
            refresh_token: tokens.refresh_token,
            access_token: tokens.access_token,
            access_token_expires_at: tokens.expires_at
          })

        text(
          conn,
          "Connected. Now set the availability + target calendar ids in scheduling_credentials."
        )

      {:error, reason} ->
        conn |> put_status(400) |> text("OAuth failed: #{inspect(reason)}")
    end
  end

  def callback(conn, _), do: conn |> put_status(400) |> text("Missing code")

  defp require_setup_token(conn, _opts) do
    expected = Application.get_env(:music_studio, MusicStudio.Scheduling)[:setup_token]

    if is_binary(expected) and expected != "" and conn.params["token"] == expected do
      conn
    else
      conn |> put_status(401) |> text("Unauthorized") |> halt()
    end
  end
end
