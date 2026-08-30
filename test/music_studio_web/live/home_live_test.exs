defmodule MusicStudioWeb.HomeLiveTest do
  use MusicStudioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MusicStudio.Leads

  test "renders the marketing sections and rates", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Music lessons for every age and stage."
    assert html =~ "Lessons &amp; Rates"
    assert html =~ "$60"
    assert html =~ "Payment by cash or e-transfer."
  end

  test "a valid inquiry persists a lead and shows confirmation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    html =
      lv
      |> form("form",
        lead: %{
          name: "Sam Learner",
          email: "sam@example.com",
          instrument: "piano",
          message: "Weekly lessons"
        }
      )
      |> render_submit()

    assert html =~ "your inquiry has been sent"

    assert [%Leads.Lead{name: "Sam Learner", email: "sam@example.com", instrument: "piano"}] =
             Leads.list_leads()
  end

  test "an invalid inquiry shows errors and persists nothing", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    html =
      lv
      |> form("form", lead: %{name: "", email: "not-an-email", instrument: ""})
      |> render_submit()

    assert html =~ "must be a valid email"
    assert Leads.list_leads() == []
  end
end
