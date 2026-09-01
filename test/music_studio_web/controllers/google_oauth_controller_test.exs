defmodule MusicStudioWeb.GoogleOAuthControllerTest do
  use MusicStudioWeb.ConnCase, async: false

  setup do
    prev = Application.get_env(:music_studio, MusicStudio.Scheduling)

    Application.put_env(
      :music_studio,
      MusicStudio.Scheduling,
      Keyword.merge(prev,
        setup_token: "secret",
        google_client_id: "cid",
        google_redirect_uri: "http://localhost/cb",
        google_auth_url: "https://accounts.google.com/o/oauth2/v2/auth"
      )
    )

    on_exit(fn -> Application.put_env(:music_studio, MusicStudio.Scheduling, prev) end)
    :ok
  end

  test "connect without the setup token is rejected", %{conn: conn} do
    conn = get(conn, "/admin/google/connect")
    assert conn.status == 401
  end

  test "connect with the setup token redirects to Google", %{conn: conn} do
    conn = get(conn, "/admin/google/connect?token=secret")
    assert redirected_to(conn) =~ "accounts.google.com"
  end
end
