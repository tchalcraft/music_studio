defmodule MusicStudio.Scheduling.GoogleCalendarTest do
  use MusicStudio.DataCase, async: false

  import MusicStudio.SchedulingStubs

  alias MusicStudio.Scheduling.GoogleCalendar

  setup do
    service_account_config()
    :ok
  end

  test "list_events parses start/end dateTimes into UTC intervals" do
    stub_google(fn conn ->
      Req.Test.json(conn, %{
        "items" => [
          %{
            "start" => %{"dateTime" => "2026-09-10T15:00:00-07:00"},
            "end" => %{"dateTime" => "2026-09-10T17:00:00-07:00"}
          }
        ]
      })
    end)

    assert {:ok, [%{starts_at: s, ends_at: e}]} =
             GoogleCalendar.list_events("cal-1", DateTime.utc_now(), DateTime.utc_now())

    assert DateTime.to_iso8601(s) == "2026-09-10T22:00:00Z"
    assert DateTime.to_iso8601(e) == "2026-09-11T00:00:00Z"
  end

  test "insert_event returns the created event id" do
    stub_google(fn conn -> Req.Test.json(conn, %{"id" => "evt-9"}) end)

    assert {:ok, "evt-9"} =
             GoogleCalendar.insert_event("cal-1", %{
               summary: "Piano",
               description: "d",
               location: "Studio",
               starts_at: DateTime.utc_now(),
               ends_at: DateTime.add(DateTime.utc_now(), 3600, :second),
               timezone: "America/Vancouver",
               attendee_email: "sam@example.com",
               send_updates: "all"
             })
  end
end
