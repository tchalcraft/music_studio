defmodule MusicStudio.Scheduling.CreateSeriesTest do
  use MusicStudio.DataCase, async: false
  import Swoosh.TestAssertions
  import MusicStudio.SchedulingStubs

  alias MusicStudio.Catalog
  alias MusicStudio.Repo
  alias MusicStudio.Scheduling
  alias MusicStudio.Teaching.Lesson

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
          Req.Test.json(conn, %{"id" => "evt-#{System.unique_integer([:positive])}"})
      end
    end)

    :ok
  end

  test "books a weekly series: one enrollment, a lesson per week, one email" do
    start = late_series_start()

    first = Scheduling.Recurrence.occurrence_utc(start, ~T[16:00:00], "America/Vancouver")

    {:ok, %{enrollment: enr, lessons: lessons}} =
      Scheduling.create_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1,
        name: "Sam Lee",
        email: "sam@example.com",
        phone: "604"
      })

    # The last four Tuesdays on/before June 30 → 4 weeks (term end June 30).
    assert length(lessons) == 4
    assert enr.status == :active
    assert enr.ended_on == Scheduling.Recurrence.term_end(start)
    assert enr.booking_token
    assert Enum.all?(lessons, &(&1.enrollment_id == enr.id))
    assert Repo.aggregate(from(l in Lesson, where: l.enrollment_id == ^enr.id), :count) == 4
    assert_email_sent(fn e -> e.subject =~ "lessons" or e.subject =~ "series" end)
  end

  test "a custom end date (#16) is persisted as ended_on and bounds the lessons" do
    start = early_series_start()
    # 4 weeks after the start → 5 weekly Tuesdays inclusive.
    custom_end = Date.add(start, 4 * 7)

    first = Scheduling.Recurrence.occurrence_utc(start, ~T[16:00:00], "America/Vancouver")

    {:ok, %{enrollment: enr, lessons: lessons}} =
      Scheduling.create_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1,
        ends_on: custom_end,
        name: "Sam Lee",
        email: "sam@example.com",
        phone: "604"
      })

    # start .. start+4w inclusive = 5 lessons; the enrollment records the chosen end.
    assert enr.ended_on == custom_end
    assert length(lessons) == 5
  end

  test "persists google_event_id for each series lesson" do
    start = late_series_start()

    first = Scheduling.Recurrence.occurrence_utc(start, ~T[16:00:00], "America/Vancouver")

    {:ok, %{lessons: lessons}} =
      Scheduling.create_series(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        first_starts_at: first,
        interval_weeks: 1,
        name: "Sam Lee",
        email: "sam@example.com",
        phone: "604"
      })

    # Reload lessons from DB to get persisted google_event_id
    persisted_lessons =
      Repo.all(from(l in Lesson, where: l.id in ^Enum.map(lessons, & &1.id)))

    # Each lesson should have a google_event_id set
    assert Enum.all?(persisted_lessons, &(&1.google_event_id != nil))
    assert Enum.all?(persisted_lessons, &String.starts_with?(&1.google_event_id, "evt-"))
  end
end
