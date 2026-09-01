defmodule MusicStudio.SchedulingTest do
  use MusicStudio.DataCase, async: false
  import Swoosh.TestAssertions

  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}
  alias MusicStudio.{Catalog, Teaching}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

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

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google",
        refresh_token: "rt",
        access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "avail-cal",
        target_calendar_id: "avail-cal"
      })

    :ok
  end

  test "create_booking creates a student + scheduled lesson, event, and emails" do
    Req.Test.stub(GoogleAuth, fn conn -> Req.Test.json(conn, %{"id" => "evt-1"}) end)

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
    Req.Test.stub(GoogleAuth, fn conn -> Req.Test.json(conn, %{"id" => "evt-1"}) end)
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
end
