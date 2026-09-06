defmodule MusicStudioWeb.BookingManageLiveTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

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

  test "a series manage page lists upcoming lessons and can skip one", %{
    conn: conn,
    series: %{enrollment: enr, lessons: lessons}
  } do
    {:ok, view, html} = live(conn, "/book/manage/#{enr.booking_token}")
    assert html =~ "Your lesson series"

    target = hd(lessons)
    assert render(view) =~ target.booking_token

    render_click(view, "skip", %{"token" => target.booking_token})
    refute render(view) =~ target.booking_token
  end

  describe "single-lesson reschedule (#15)" do
    setup do
      starts_at =
        Scheduling.Recurrence.occurrence_utc(~D[2027-06-07], ~T[16:00:00], "America/Vancouver")

      {:ok, lesson} =
        Scheduling.create_booking(%{
          instrument_slug: "piano",
          duration_minutes: 60,
          starts_at: starts_at,
          name: "Jo",
          email: "jo@example.com",
          phone: nil
        })

      %{lesson: lesson, starts_at: starts_at}
    end

    test "picking a new time reveals slots and moves the lesson", %{
      conn: conn,
      lesson: lesson,
      starts_at: starts_at
    } do
      {:ok, view, _html} = live(conn, "/book/manage/#{lesson.booking_token}")

      # Reveal the reschedule picker.
      html = render_click(view, "start_reschedule", %{})
      assert html =~ "Pick a new time" or html =~ "Choose a new time"

      # Find an available slot different from the current booking.
      {:ok, slots} =
        Scheduling.list_available_slots(%{
          instrument_slug: "piano",
          duration_minutes: 60,
          from: Date.add(Date.utc_today(), 1),
          to: Date.add(Date.utc_today(), 21)
        })

      new_slot = Enum.find(slots, &(DateTime.compare(&1.starts_at, starts_at) != :eq))
      assert new_slot, "expected at least one alternate available slot"

      render_click(view, "pick_new_slot", %{"start" => DateTime.to_iso8601(new_slot.starts_at)})

      updated = Scheduling.get_lesson_by_token(lesson.booking_token)
      assert DateTime.compare(updated.scheduled_start, new_slot.starts_at) == :eq
      assert render(view) =~ "moved" or render(view) =~ "rescheduled"
    end
  end
end
