defmodule MusicStudioWeb.BookingLiveRecurringTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import MusicStudio.SchedulingStubs

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling.Recurrence

  @tz "America/Vancouver"

  setup do
    service_account_config()

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})

    {:ok, _} =
      Catalog.create_offering(%{
        name: "60",
        duration_minutes: 60,
        price_cents: 7000,
        active: true
      })

    # Weekday 3–6pm PT blocks across whatever range is queried (so the picker + the
    # term projection both have availability).
    stub_google(fn conn ->
      case conn.method do
        "GET" ->
          conn = Plug.Conn.fetch_query_params(conn)
          {:ok, tmin, _} = DateTime.from_iso8601(conn.query_params["timeMin"])
          {:ok, tmax, _} = DateTime.from_iso8601(conn.query_params["timeMax"])
          dmin = DateTime.to_date(tmin)
          dmax = Enum.min([DateTime.to_date(tmax), Date.add(dmin, 400)], Date)

          items =
            for d <- Date.range(dmin, dmax), Date.day_of_week(d) in 1..5 do
              ds = Date.to_iso8601(d)

              %{
                "start" => %{"dateTime" => ds <> "T15:00:00-07:00"},
                "end" => %{"dateTime" => ds <> "T18:00:00-07:00"}
              }
            end

          Req.Test.json(conn, %{"items" => items})

        _ ->
          Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)

    :ok
  end

  defp studio_today, do: DateTime.utc_now() |> DateTime.shift_zone!(@tz) |> DateTime.to_date()

  # Earliest bookable occurrence of `weekday` (1=Mon..7=Sun): from tomorrow (24h notice).
  defp default_start(weekday) do
    floor = Date.add(studio_today(), 1)
    Date.add(floor, rem(weekday - Date.day_of_week(floor) + 7, 7))
  end

  # A Wednesday (weekday 3, always a weekday) ≥ a week out, at 3:00 PM PT — a valid pattern.
  defp wednesday_pattern_iso do
    today = studio_today()
    offset = rem(3 - Date.day_of_week(today) + 7, 7)
    wed = Date.add(today, offset + 7)
    wed |> Recurrence.occurrence_utc(~T[15:00:00], @tz) |> DateTime.to_iso8601()
  end

  defp start_schedule(conn) do
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_change(view, "set_cadence", %{"cadence" => "weekly"})
    view
  end

  test "weekly cadence shows a full-week day & time picker with the terms", %{conn: conn} do
    view = start_schedule(conn)
    html = render(view)

    assert html =~ "usual day"
    assert html =~ "billed monthly"
    assert html =~ "Wednesday"
    assert has_element?(view, ~s(button[phx-click="pick_pattern"]))
  end

  test "picking the day & time reveals the start-date step with a preview", %{conn: conn} do
    view = start_schedule(conn)

    html = render_click(view, "pick_pattern", %{"start" => wednesday_pattern_iso()})

    assert html =~ "Starts on"
    assert html =~ Calendar.strftime(default_start(3), "%A, %b %-d")
    assert html =~ "lessons through Jun 30"
  end

  test "stepping the start date moves it one week and back", %{conn: conn} do
    view = start_schedule(conn)
    render_click(view, "pick_pattern", %{"start" => wednesday_pattern_iso()})

    render_click(view, "start_later", %{})
    assert render(view) =~ Calendar.strftime(Date.add(default_start(3), 7), "%A, %b %-d")

    render_click(view, "start_earlier", %{})
    assert render(view) =~ Calendar.strftime(default_start(3), "%A, %b %-d")
  end

  test "Continue advances to Your details", %{conn: conn} do
    view = start_schedule(conn)
    render_click(view, "pick_pattern", %{"start" => wednesday_pattern_iso()})

    html = render_click(view, "to_details", %{})
    assert html =~ "Your name"
    assert has_element?(view, ~s([aria-current="step"]), "Your details")
  end

  test "booking a weekly series shows the series confirmation", %{conn: conn} do
    view = start_schedule(conn)
    render_click(view, "pick_pattern", %{"start" => wednesday_pattern_iso()})
    render_click(view, "to_details", %{})

    html =
      render_submit(view, "book", %{
        "booking" => %{"name" => "Sam Lee", "email" => "sam@example.com", "phone" => ""}
      })

    assert html =~ "Your series is booked"
    assert html =~ "lessons through June 30"
  end
end
