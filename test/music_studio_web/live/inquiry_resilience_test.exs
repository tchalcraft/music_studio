defmodule MusicStudioWeb.InquiryResilienceTest do
  # Regression tests for GH #3 "send inquiry not working": a failing/misconfigured mailer
  # (e.g. the provider rejecting the From address) must NOT crash the inquiry submit or
  # hide the confirmation. The lead is persisted before the email is sent, so the visitor
  # should always see the confirmation and the delivery error should be logged.
  #
  # async: false — these tests swap the global MusicStudio.Mailer adapter, so they must run
  # serially rather than concurrently with tests that rely on the Swoosh test adapter.
  use MusicStudioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  alias MusicStudio.Leads
  alias MusicStudio.Leads.Notifier

  # A mailer adapter that always raises, simulating a provider/adapter blowing up at
  # delivery time (the exact failure mode that crashed the submit before the fix).
  defmodule RaisingAdapter do
    @moduledoc false
    def validate_config(_config), do: :ok
    def deliver(_email, _config), do: raise("simulated mailer failure")
  end

  @valid %{
    name: "Sam Learner",
    email: "sam@example.com",
    instrument: "piano",
    message: "Weekly lessons"
  }

  setup do
    original = Application.get_env(:music_studio, MusicStudio.Mailer)
    Application.put_env(:music_studio, MusicStudio.Mailer, adapter: RaisingAdapter)
    on_exit(fn -> Application.put_env(:music_studio, MusicStudio.Mailer, original) end)
    :ok
  end

  test "Notifier returns {:error, _} and logs instead of raising when delivery crashes" do
    {:ok, lead} = Leads.create_lead(@valid)

    {result, log} = with_log(fn -> Notifier.deliver_inquiry_notification(lead) end)

    assert {:error, {:exception, %RuntimeError{}}} = result
    assert log =~ "crashed"
  end

  test "inquiry form still confirms and persists the lead when email delivery fails", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/")

    {html, _log} =
      with_log(fn ->
        lv |> form("form", lead: @valid) |> render_submit()
      end)

    assert html =~ "your inquiry has been sent"
    assert [%Leads.Lead{name: "Sam Learner", email: "sam@example.com"}] = Leads.list_leads()
  end
end
