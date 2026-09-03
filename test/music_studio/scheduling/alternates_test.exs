defmodule MusicStudio.Scheduling.AlternatesTest do
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

  test "week_alternates returns open slots that week and add_series_lesson books one", %{
    series: %{enrollment: enr}
  } do
    {:ok, slots} =
      Scheduling.week_alternates(
        %{instrument_slug: "piano", duration_minutes: 60},
        ~D[2027-06-08]
      )

    assert slots != []
    alt = hd(slots)
    assert {:ok, lesson} = Scheduling.add_series_lesson(enr.booking_token, alt.starts_at)
    assert lesson.enrollment_id == enr.id
    assert lesson.status == :scheduled
  end
end
