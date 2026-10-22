defmodule MusicStudioWeb.SecurityPlugsTest do
  use MusicStudioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MusicStudioWeb.Plugs.{AdminAuth, ScannerBlock}

  defp basic_auth(conn, user, pass) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(user, pass))
  end

  describe "/cms admin gate" do
    test "rejects requests without credentials", %{conn: conn} do
      conn = get(conn, "/cms")
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") != []
    end

    test "rejects wrong credentials", %{conn: conn} do
      conn = conn |> basic_auth("admin", "nope") |> get("/cms")
      assert conn.status == 401
    end

    test "fails closed when credentials are not configured", %{conn: conn} do
      original = Application.get_env(:music_studio, :admin_auth)
      Application.put_env(:music_studio, :admin_auth, username: "admin", password: nil)
      on_exit(fn -> Application.put_env(:music_studio, :admin_auth, original) end)

      conn = conn |> basic_auth("admin", "") |> get("/cms")
      assert conn.status == 401
    end

    test "admits the configured credentials", %{conn: conn} do
      conn = conn |> basic_auth("admin", "test-admin-password") |> get("/cms")
      assert conn.status in [200, 302]
      assert get_session(conn, "admin_authenticated") == true
    end

    test "on_mount refuses LiveView sessions that skipped the plug" do
      socket = %Phoenix.LiveView.Socket{}

      assert {:halt, _} = AdminAuth.on_mount(:require_admin, %{}, %{}, socket)

      assert {:cont, ^socket} =
               AdminAuth.on_mount(:require_admin, %{}, %{"admin_authenticated" => true}, socket)
    end
  end

  describe "scanner block" do
    for path <-
          ~w(/wp-admin/install.php /xmlrpc.php /.env /.git/config /_next/static /index.php/x /WP-LOGIN.PHP) do
      test "404s #{path}", %{conn: conn} do
        conn = get(conn, unquote(path))
        assert conn.status == 404
        assert conn.halted
      end
    end

    test "leaves real pages alone" do
      for path <- ~w(/ /book /book/manage/abc /invoices/x/pay /cms /sitemap.xml /up) do
        refute ScannerBlock.scanner_path?(path), path
      end
    end
  end

  describe "/up" do
    test "answers 200 without a session cookie", %{conn: conn} do
      conn = get(conn, "/up")
      assert conn.status == 200
      assert conn.resp_body == "ok"
      assert get_resp_header(conn, "set-cookie") == []
    end
  end

  test "public pages still render", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, "/")
  end
end
