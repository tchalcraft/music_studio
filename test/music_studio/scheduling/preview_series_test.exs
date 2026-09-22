defmodule MusicStudio.Scheduling.PreviewSeriesTest do
  use MusicStudio.DataCase, async: false

  import MusicStudio.SchedulingStubs

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling

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

    :ok
  end

  test "projects weekly occurrences to June 30 and marks the open ones bookable" do
    # Availability calendar: for each day it queries, return a 15:00-18:00 PT block for THAT day.
    stub_google(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      day = conn.query_params["timeMin"] |> String.slice(0, 10)

      Req.Test.json(conn, %{
        "items" => [
          %{
            "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
            "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
          }
        ]
      })
    end)

    start = early_series_start()
    term_end = Scheduling.Recurrence.term_end(start)

    first = Scheduling.Recurrence.occurrence_utc(start, ~T[16:00:00], "America/Vancouver")

    {:ok, preview} =
      Scheduling.preview_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1
      })

    assert preview.term_end == term_end
    assert preview.ended_on == term_end
    assert preview.start_date == start
    # Every Tuesday from an early-September start to the following June 30 is open in this stub.
    assert length(preview.bookable) >= 40
    assert preview.conflicted == []
  end

  test "a custom end date (#16) shortens the series and is echoed as ended_on" do
    stub_all_days_open()

    start = early_series_start()
    # 13 weeks after the start → 14 weekly Tuesdays inclusive, well within the term.
    custom_end = Date.add(start, 13 * 7)

    first = Scheduling.Recurrence.occurrence_utc(start, ~T[16:00:00], "America/Vancouver")

    {:ok, preview} =
      Scheduling.preview_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1,
        ends_on: custom_end
      })

    # start .. start+13w inclusive = 14 lessons.
    assert length(preview.bookable) == 14
    assert preview.ended_on == custom_end
    # term_end still reports the school-year cap (Jun 30) for the UI bound.
    assert preview.term_end == Scheduling.Recurrence.term_end(start)

    last = preview.bookable |> List.last() |> DateTime.shift_zone!("America/Vancouver")
    assert DateTime.to_date(last) == custom_end
  end

  test "a custom end past June 30 is clamped to the school-year term end (#16)" do
    stub_all_days_open()

    start = early_series_start()
    term_end = Scheduling.Recurrence.term_end(start)

    first = Scheduling.Recurrence.occurrence_utc(start, ~T[16:00:00], "America/Vancouver")

    {:ok, preview} =
      Scheduling.preview_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1,
        # Well past the school-year end → should clamp to the term end.
        ends_on: Date.add(term_end, 180)
      })

    assert preview.ended_on == term_end
    assert length(preview.bookable) >= 40
  end

  # Availability stub: for each queried day, return a 15:00-18:00 PT open block.
  defp stub_all_days_open do
    stub_google(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      day = conn.query_params["timeMin"] |> String.slice(0, 10)

      Req.Test.json(conn, %{
        "items" => [
          %{
            "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
            "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
          }
        ]
      })
    end)
  end
end
