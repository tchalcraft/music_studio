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

    first =
      Scheduling.Recurrence.occurrence_utc(~D[2026-09-08], ~T[16:00:00], "America/Vancouver")

    {:ok, preview} =
      Scheduling.preview_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1
      })

    assert preview.term_end == ~D[2027-06-30]
    assert preview.start_date == ~D[2026-09-08]
    # Every Tuesday Sep 8 2026 -> Jun 29 2027 is open in this stub.
    assert length(preview.bookable) >= 40
    assert preview.conflicted == []
  end
end
