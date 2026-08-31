defmodule MusicStudio.TeachingTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Catalog
  alias MusicStudio.Teaching
  alias MusicStudio.Teaching.Enrollment
  alias MusicStudio.Teaching.Lesson
  alias MusicStudio.Teaching.Student

  defp fixtures do
    {:ok, teacher} = Catalog.create_teacher(%{name: "Tristan"})
    {:ok, instrument} = Catalog.create_instrument(%{name: "Voice", slug: "voice"})

    {:ok, offering} =
      Catalog.create_offering(%{
        name: "60",
        duration_minutes: 60,
        price_cents: 6000,
        currency: "CAD"
      })

    {:ok, location} = Catalog.create_location(%{name: "Studio", kind: :in_person})
    %{teacher: teacher, instrument: instrument, offering: offering, location: location}
  end

  test "create_student/1 requires a name and defaults status" do
    assert {:error, changeset} = Teaching.create_student(%{})
    assert "can't be blank" in errors_on(changeset).first_name

    assert {:ok, %Student{} = s} = Teaching.create_student(%{first_name: "Sam", last_name: "Lee"})
    assert s.status == :prospective
  end

  test "enrollment → lesson round-trips with associations" do
    %{teacher: teacher, instrument: instrument, offering: offering, location: location} =
      fixtures()

    {:ok, student} =
      Teaching.create_student(%{first_name: "Sam", last_name: "Lee", status: :active})

    assert {:ok, %Enrollment{} = enrollment} =
             Teaching.create_enrollment(%{
               student_id: student.id,
               teacher_id: teacher.id,
               instrument_id: instrument.id,
               offering_id: offering.id,
               location_id: location.id,
               status: :active,
               started_on: Date.utc_today()
             })

    assert {:ok, %Lesson{} = lesson} =
             Teaching.create_lesson(%{
               enrollment_id: enrollment.id,
               student_id: student.id,
               teacher_id: teacher.id,
               instrument_id: instrument.id,
               offering_id: offering.id,
               location_id: location.id,
               scheduled_start: DateTime.utc_now() |> DateTime.truncate(:second),
               duration_minutes: 60,
               price_cents: 6000,
               status: :scheduled
             })

    assert lesson.status == :scheduled
    assert [%Lesson{}] = Teaching.list_lessons()
  end

  test "enrollment requires student, teacher, and instrument" do
    assert {:error, changeset} = Teaching.create_enrollment(%{status: :active})
    errs = errors_on(changeset)
    assert "can't be blank" in errs.student_id
    assert "can't be blank" in errs.teacher_id
    assert "can't be blank" in errs.instrument_id
  end
end
