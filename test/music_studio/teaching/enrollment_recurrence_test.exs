defmodule MusicStudio.Teaching.EnrollmentRecurrenceTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Catalog
  alias MusicStudio.Repo
  alias MusicStudio.Teaching
  alias MusicStudio.Teaching.Enrollment

  test "an enrollment stores a recurrence schedule + series token" do
    {:ok, teacher} = Catalog.create_teacher(%{name: "T", active: true})
    {:ok, piano} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, student} = Teaching.create_student(%{first_name: "S", status: "prospective"})

    attrs = %{
      status: :active,
      started_on: ~D[2026-09-08],
      ended_on: ~D[2027-06-30],
      recurrence_interval_weeks: 1,
      recurrence_weekday: 2,
      recurrence_time: ~T[16:00:00],
      recurrence_timezone: "America/Vancouver",
      booking_token: "series-tok-1",
      contact_email: "sam@example.com",
      teacher_id: teacher.id,
      student_id: student.id,
      instrument_id: piano.id
    }

    assert {:ok, e} = %Enrollment{} |> Enrollment.changeset(attrs) |> Repo.insert()
    assert e.recurrence_interval_weeks == 1
    assert e.recurrence_time == ~T[16:00:00]
    assert e.booking_token == "series-tok-1"

    {:error, cs} =
      %Enrollment{} |> Enrollment.changeset(%{attrs | student_id: student.id}) |> Repo.insert()

    assert "has already been taken" in errors_on(cs).booking_token
  end
end
