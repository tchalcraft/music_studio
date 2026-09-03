defmodule MusicStudio.Scheduling.SeriesManageTest do
  use MusicStudio.DataCase, async: false

  import MusicStudio.SchedulingStubs

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling

  setup do
    service_account_config()

    {:ok, _} = Catalog.create_teacher(%{name: "T", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})

    {:ok, _} =
      Catalog.create_offering(%{
        name: "60",
        duration_minutes: 60,
        price_cents: 7000,
        active: true
      })

    stub_google(fn conn ->
      case conn.method do
        "GET" ->
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

        _ ->
          Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)

    first =
      Scheduling.Recurrence.occurrence_utc(~D[2027-06-01], ~T[16:00:00], "America/Vancouver")

    {:ok, series} =
      Scheduling.create_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1,
        name: "Sam",
        email: "sam@example.com",
        phone: nil
      })

    %{series: series}
  end

  test "skip one occurrence: that lesson is cancelled, the series remains", %{
    series: %{lessons: lessons, enrollment: enr}
  } do
    target = hd(lessons)
    assert {:ok, skipped} = Scheduling.skip_occurrence(target.booking_token)
    assert skipped.status == :cancelled
    assert Scheduling.get_series_by_token(enr.booking_token).status == :active
  end

  test "cancel series: enrollment cancelled and future lessons cancelled", %{
    series: %{enrollment: enr}
  } do
    assert {:ok, cancelled} = Scheduling.cancel_series(enr.booking_token)
    assert cancelled.status == :cancelled
    assert Enum.empty?(Scheduling.list_series_lessons(cancelled))
  end

  test "pause skips up to 4 consecutive occurrences and holds the slot", %{
    series: %{enrollment: enr}
  } do
    from = enr.started_on
    assert {:ok, %{skipped: skipped}} = Scheduling.pause_series(enr.booking_token, from)
    assert length(skipped) <= 4
    assert Enum.all?(skipped, &(&1.status == :cancelled))
    # enrollment still active -> slot still held
    assert Scheduling.get_series_by_token(enr.booking_token).status == :active
  end
end
