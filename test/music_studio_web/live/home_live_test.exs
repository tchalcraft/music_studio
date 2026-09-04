defmodule MusicStudioWeb.HomeLiveTest do
  use MusicStudioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MusicStudio.Leads

  test "renders the marketing sections and rates", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Music lessons for every age and stage."
    assert html =~ "Lessons &amp; Rates"
    assert html =~ "$70"
    assert html =~ "Payment by cash or e-transfer."
  end

  test "the homepage links to the booking page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Book a session"
    assert html =~ "Book a lesson online"
    assert has_element?(view, ~s(a[href="/book"]))
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

  test "the page includes meta tags for SEO", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "name=\"description\""
    assert html =~ "property=\"og:title\""
    assert html =~ "property=\"og:description\""
    assert html =~ "property=\"og:type\""
    assert html =~ "name=\"twitter:card\" content=\"summary_large_image\""
    assert html =~ "type=\"application/ld+json\""
    assert html =~ "@context"
    assert html =~ "MusicSchool"
  end
end
