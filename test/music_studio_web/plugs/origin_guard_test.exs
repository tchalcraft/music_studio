defmodule MusicStudioWeb.OriginGuardTest do
  # Mutates app env, so not async.
  use MusicStudioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

    test "passes the right header through", %{conn: conn} do
      conn = conn |> put_req_header("x-origin-auth", @secret) |> get("/book")
      assert conn.status == 200
    end

    test "still answers /up for Render's direct health probe", %{conn: conn} do
      assert get(conn, "/up").status == 200
    end
  end

  describe "LiveView on_mount (socket path)" do
    alias MusicStudioWeb.Plugs.OriginGuard

    defp socket(connected?, x_headers) do
      %Phoenix.LiveView.Socket{
        transport_pid: if(connected?, do: self()),
        private: %{connect_info: %{x_headers: x_headers}}
      }
    end

    setup do: with_secret(@secret)

    test "halts a connected mount without the header" do
      assert {:halt, _} = OriginGuard.on_mount(:default, %{}, %{}, socket(true, []))
    end

    test "halts a connected mount with a wrong header" do
      assert {:halt, _} =
               OriginGuard.on_mount(:default, %{}, %{}, socket(true, [{"x-origin-auth", "nope"}]))
    end

    test "continues a connected mount with the right header" do
      assert {:cont, _} =
               OriginGuard.on_mount(
                 :default,
                 %{},
                 %{},
                 socket(true, [{"x-origin-auth", @secret}])
               )
    end

    test "continues the disconnected (HTTP) mount, which the plug already guarded" do
      assert {:cont, _} = OriginGuard.on_mount(:default, %{}, %{}, socket(false, []))
    end

    test "a full LiveView round-trip still works through the guard", %{conn: conn} do
      conn = put_req_header(conn, "x-origin-auth", @secret)
      assert {:ok, _view, _html} = live(conn, "/book")
    end
  end

  test "is a no-op when the secret is unset", %{conn: conn} do
    with_secret(nil)
    assert get(conn, "/book").status == 200
  end
end
