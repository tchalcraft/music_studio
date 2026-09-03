defmodule MusicStudioWeb.BookingLiveTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  # First availability block is far in the future so it clears the 24h min-notice window.
  # 3:00–5:00 PM PT on 2027-01-05 (UTC-08:00) → 60-min/30-grid slots at 23:00, 23:30, 00:00Z.
  @first_slot_iso "2027-01-05T23:00:00Z"

  defp stub_google do
    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{
            "items" => [
              %{
                "start" => %{"dateTime" => "2027-01-05T15:00:00-08:00"},
                "end" => %{"dateTime" => "2027-01-05T17:00:00-08:00"}
              }
            ]
          })

        _ ->
          Req.Test.json(conn, %{"id" => "evt-test"})
      end
    end)
  end

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})

    {:ok, _} =
      Catalog.create_offering(%{
        name: "60",
        duration_minutes: 60,
        price_cents: 7000,
        active: true
      })

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google",
        refresh_token: "rt",
        access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c",
        target_calendar_id: "c"
      })

    :ok
  end

  test "renders the instrument + duration picker", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    assert html =~ "Book a lesson"
    assert html =~ "Piano"
  end

  test "the step bar shows all four steps with Lesson current on mount", %{conn: conn} do
    {:ok, view, html} = live(conn, "/book")
    assert html =~ "Schedule"
    assert html =~ "Your details"
    assert html =~ "Confirmed"
    assert has_element?(view, ~s([aria-current="step"]), "Lesson")
  end

  test "choosing instrument + duration advances to the Schedule step", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")

    html =
      render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    assert html =~ "Available times"
    assert has_element?(view, ~s([aria-current="step"]), "Schedule")
  end

  test "picking a slot advances to Your details", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    html = render_click(view, "pick_slot", %{"start" => @first_slot_iso})
    assert html =~ "Your name"
    assert has_element?(view, ~s([aria-current="step"]), "Your details")
  end

  test "completing the flow shows the Confirmed step", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_click(view, "pick_slot", %{"start" => @first_slot_iso})

    html =
      render_submit(view, "book", %{
        "booking" => %{"name" => "Sam Lee", "email" => "sam@example.com", "phone" => ""}
      })

    assert html =~ "booked!"
    assert has_element?(view, ~s([aria-current="step"]), "Confirmed")
  end

  test "Back from details returns to Schedule and keeps entered details", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_click(view, "pick_slot", %{"start" => @first_slot_iso})

    render_change(view, "validate_details", %{
      "booking" => %{"name" => "Sam Lee", "email" => "", "phone" => ""}
    })

    render_click(view, "back", %{"to" => "schedule"})
    assert has_element?(view, ~s([aria-current="step"]), "Schedule")

    html = render_click(view, "pick_slot", %{"start" => @first_slot_iso})
    assert html =~ ~s(value="Sam Lee")
  end

  test "the step bar uses the branded ms- classes", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    assert html =~ ~s(class="ms-stepbar")
    assert html =~ "ms-step"
  end

  # A near-future day (clears 24h notice, within the 2-month window) gets a 3–6pm PT block.
  defp stub_on_day(date) do
    d = Date.to_iso8601(date)

    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{
            "items" => [
              %{
                "start" => %{"dateTime" => d <> "T15:00:00-07:00"},
                "end" => %{"dateTime" => d <> "T18:00:00-07:00"}
              }
            ]
          })

        _ ->
          Req.Test.json(conn, %{"id" => "evt"})
      end
    end)
  end

  test "single booking shows a month calendar grid for the available month", %{conn: conn} do
    target = Date.add(Date.utc_today(), 10)
    stub_on_day(target)
    {:ok, view, _} = live(conn, "/book")

    html =
      render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    assert html =~ Calendar.strftime(target, "%B %Y")
    assert html =~ "Su"

    assert has_element?(
             view,
             ~s(button[phx-click="pick_day"][phx-value-date="#{Date.to_iso8601(target)}"])
           )
  end

  test "clicking an available day reveals that day's times", %{conn: conn} do
    target = Date.add(Date.utc_today(), 10)
    stub_on_day(target)
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    html = render_click(view, "pick_day", %{"date" => Date.to_iso8601(target)})

    assert html =~ Calendar.strftime(target, "%A, %b")
    assert has_element?(view, ~s(button[phx-click="pick_slot"]))
  end

  test "recurring cadence shows a one-week day-by-day view", %{conn: conn} do
    target = Date.add(Date.utc_today(), 10)
    stub_on_day(target)
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    html = render_change(view, "set_cadence", %{"cadence" => "weekly"})

    assert html =~ "usual day"
    assert html =~ Calendar.strftime(target, "%A, %b")
  end

  test "the month can be navigated with next/prev", %{conn: conn} do
    target = Date.add(Date.utc_today(), 10)
    stub_on_day(target)
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    next = Date.add(Date.beginning_of_month(target), 40) |> Date.beginning_of_month()
    html = render_click(view, "next_month", %{})
    assert html =~ Calendar.strftime(next, "%B %Y")

    html = render_click(view, "prev_month", %{})
    assert html =~ Calendar.strftime(target, "%B %Y")
  end
end
