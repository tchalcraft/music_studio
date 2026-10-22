defmodule MusicStudioWeb.OriginGuardTest do
  # Mutates app env, so not async.
  use MusicStudioWeb.ConnCase, async: false

  @secret "test-origin-secret"

  defp with_secret(secret) do
    original = Application.get_env(:music_studio, :origin_auth_secret)
    Application.put_env(:music_studio, :origin_auth_secret, secret)
    on_exit(fn -> Application.put_env(:music_studio, :origin_auth_secret, original) end)
  end

  describe "with ORIGIN_AUTH_SECRET set" do
    setup do: with_secret(@secret)

    test "403s a request with no origin header", %{conn: conn} do
      conn = get(conn, "/")
      assert conn.status == 403
      assert conn.halted
    end

    test "403s a wrong origin header", %{conn: conn} do
      conn = conn |> put_req_header("x-origin-auth", "nope") |> get("/")
      assert conn.status == 403
    end

    test "passes the right header through and strips it", %{conn: conn} do
      conn = conn |> put_req_header("x-origin-auth", @secret) |> get("/book")
      assert conn.status == 200
      assert get_req_header(conn, "x-origin-auth") == []
    end

    test "still answers /up for Render's direct health probe", %{conn: conn} do
      assert get(conn, "/up").status == 200
    end
  end

  test "is a no-op when the secret is unset", %{conn: conn} do
    with_secret(nil)
    assert get(conn, "/book").status == 200
  end
end
