defmodule MusicStudioWeb.FormGuardTest do
  # Mutates app env (rate limit + Turnstile config), so not async.
  use MusicStudioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MusicStudio.Leads

  @lead %{name: "Sam Learner", email: "sam@example.com", instrument: "piano", message: "Hi"}

  defp put_env(key, value) do
    original = Application.get_env(:music_studio, key)
    Application.put_env(:music_studio, key, value)
    on_exit(fn -> Application.put_env(:music_studio, key, original) end)
  end

  defp enable_turnstile do
    put_env(:turnstile,
      site_key: "site-key",
      secret_key: "secret-key",
      req_options: [plug: {Req.Test, MusicStudio.Turnstile}]
    )
  end

  defp submit_inquiry(lv, token \\ "token") do
    lv
    |> form("form", lead: @lead)
    |> render_submit(%{"cf-turnstile-response" => token})
  end

  describe "rate limit" do
    setup do
      put_env(MusicStudio.RateLimit, enabled: true)
      # Every test conn is 127.0.0.1, so start each test from empty counters.
      :ets.delete_all_objects(MusicStudio.RateLimit)
      :ok
    end

    test "the 6th inquiry within the hour from one IP is refused", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      for _ <- 1..5, do: assert(submit_inquiry(lv) =~ "your inquiry has been sent")

      assert submit_inquiry(lv) =~ "Too many attempts"
      assert length(Leads.list_leads()) == 5
    end
  end

  describe "Turnstile" do
    setup do: enable_turnstile()

    test "renders the widget in the form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(
               lv,
               ~s(#inquiry-turnstile[phx-hook="Turnstile"][data-sitekey="site-key"])
             )
    end

    test "a token Cloudflare accepts lets the inquiry through", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      Req.Test.stub(MusicStudio.Turnstile, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "response=token"
        assert body =~ "secret=secret-key"
        Req.Test.json(conn, %{"success" => true})
      end)

      Req.Test.allow(MusicStudio.Turnstile, self(), lv.pid)

      assert submit_inquiry(lv) =~ "your inquiry has been sent"
      assert [%Leads.Lead{}] = Leads.list_leads()
    end

    test "a rejected token blocks the inquiry", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      Req.Test.stub(MusicStudio.Turnstile, fn conn ->
        Req.Test.json(conn, %{"success" => false, "error-codes" => ["invalid-input-response"]})
      end)

      Req.Test.allow(MusicStudio.Turnstile, self(), lv.pid)

      assert submit_inquiry(lv) =~ "quick security check"
      assert Leads.list_leads() == []
    end

    test "a missing token is refused without calling Cloudflare", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      Req.Test.stub(MusicStudio.Turnstile, fn _conn ->
        flunk("siteverify should not be called")
      end)

      Req.Test.allow(MusicStudio.Turnstile, self(), lv.pid)

      assert submit_inquiry(lv, "") =~ "quick security check"
      assert Leads.list_leads() == []
    end

    test "if Cloudflare is unreachable the inquiry is allowed (fail open)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      Req.Test.stub(MusicStudio.Turnstile, &Req.Test.transport_error(&1, :econnrefused))
      Req.Test.allow(MusicStudio.Turnstile, self(), lv.pid)

      assert submit_inquiry(lv) =~ "your inquiry has been sent"
      assert [%Leads.Lead{}] = Leads.list_leads()
    end
  end

  test "with Turnstile unconfigured the widget isn't rendered and inquiries work", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")
    refute has_element?(lv, "#inquiry-turnstile")
    assert submit_inquiry(lv, nil) =~ "your inquiry has been sent"
  end
end
