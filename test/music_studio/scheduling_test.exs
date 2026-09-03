defmodule MusicStudio.SchedulingTest do
  use MusicStudio.DataCase, async: false
  import Swoosh.TestAssertions
  import MusicStudio.SchedulingStubs

  alias MusicStudio.{Catalog, Teaching}
  alias MusicStudio.Scheduling

  setup do
    service_account_config()

    {:ok, _teacher} =
      Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})

    {:ok, _piano} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})

    {:ok, _off} =
      Catalog.create_offering(%{
        name: "60-minute lesson",
        duration_minutes: 60,
        price_cents: 7000,
        currency: "CAD",
        active: true
      })

    :ok
  end

  test "create_booking creates a student + scheduled lesson, event, and emails" do
    stub_google(fn conn -> Req.Test.json(conn, %{"id" => "evt-1"}) end)

    starts = DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC")

    assert {:ok, lesson} =
             Scheduling.create_booking(%{
               instrument_slug: "piano",
               duration_minutes: 60,
               starts_at: starts,
               name: "Sam Lee",
               email: "sam@example.com",
               phone: "555"
             })

    assert lesson.status == :scheduled
    assert lesson.price_cents == 7000
    assert lesson.google_event_id == "evt-1"
    assert Teaching.get_student_by_email("sam@example.com")
    assert_email_sent(fn e -> e.subject =~ "booked" end)
  end

  test "a second booking for the same slot is rejected" do
    stub_google(fn conn -> Req.Test.json(conn, %{"id" => "evt-1"}) end)
    starts = DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC")

    attrs = %{
      instrument_slug: "piano",
      duration_minutes: 60,
      starts_at: starts,
      name: "A",
      email: "a@x.com",
      phone: nil
    }

    assert {:ok, _} = Scheduling.create_booking(attrs)
    assert {:error, :slot_taken} = Scheduling.create_booking(%{attrs | email: "b@x.com"})
  end

  test "cancelling a booking emails the visitor" do
    stub_google(fn conn -> Req.Test.json(conn, %{"id" => "evt-1"}) end)

    starts = DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC")

    {:ok, lesson} =
      Scheduling.create_booking(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        starts_at: starts,
        name: "Sam Lee",
        email: "sam@example.com",
        phone: nil
      })

    # Drain the confirmation + notification emails from the booking so the cancellation
    # is next in the mailbox (assert_email_sent inspects the first queued email).
    flush_emails()

    assert {:ok, _} = Scheduling.cancel_booking(lesson.booking_token)

    assert_email_sent(fn e ->
      e.to == [{"Sam Lee", "sam@example.com"}] and e.subject =~ "cancel"
    end)
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
