defmodule MusicStudio.Scheduling.HeldSlotsTest do
  use MusicStudio.DataCase, async: false

  import MusicStudio.SchedulingStubs

  alias MusicStudio.{Catalog, Repo, Teaching}
  alias MusicStudio.Scheduling
  alias MusicStudio.Teaching.Enrollment

  setup do
    service_account_config()

    {:ok, teacher} =
      Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})

    {:ok, piano} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})

    {:ok, off} =
      Catalog.create_offering(%{
        name: "30",
        duration_minutes: 30,
        price_cents: 3500,
        active: true
      })

    {:ok, student} = Teaching.create_student(%{first_name: "S", status: "prospective"})

    # A paused series: Tuesdays 16:00 PT, holding the slot for the whole term.
    {:ok, _enr} =
      %Enrollment{}
      |> Enrollment.changeset(%{
        status: :paused,
        started_on: ~D[2026-09-08],
        ended_on: ~D[2027-06-30],
        recurrence_interval_weeks: 1,
        recurrence_weekday: 2,
        recurrence_time: ~T[16:00:00],
        recurrence_timezone: "America/Vancouver",
        booking_token: "series-1",
        contact_email: "held@example.com",
        teacher_id: teacher.id,
        student_id: student.id,
        instrument_id: piano.id,
        offering_id: off.id
      })
      |> Repo.insert()

    %{}
  end

  test "a paused series' recurring time is withheld from availability" do
    # Availability calendar wide open on Tue Sep 15 2026, 15:00-18:00 PT.
    stub_google(fn conn ->
      Req.Test.json(conn, %{
        "items" => [
          %{
            "start" => %{"dateTime" => "2026-09-15T15:00:00-07:00"},
            "end" => %{"dateTime" => "2026-09-15T18:00:00-07:00"}
          }
        ]
      })
    end)

    {:ok, slots} =
      Scheduling.list_available_slots(%{
        instrument_slug: "piano",
        duration_minutes: 30,
        from: ~D[2026-09-15],
        to: ~D[2026-09-15]
      })

    starts =
      Enum.map(
        slots,
        &(&1.starts_at
          |> DateTime.shift_zone!("America/Vancouver")
          |> Calendar.strftime("%-I:%M %p"))
      )

    # 16:00 held (buffer 15m also blocks 15:30 and 16:30); 15:00 and 17:00 remain.
    refute "4:00 PM" in starts
    refute "3:30 PM" in starts
    refute "4:30 PM" in starts
    assert "3:00 PM" in starts
    assert "5:00 PM" in starts
  end
end
