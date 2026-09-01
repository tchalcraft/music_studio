defmodule MusicStudio.Scheduling.BookingDbTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Catalog
  alias MusicStudio.Repo
  alias MusicStudio.Teaching
  alias MusicStudio.Teaching.Lesson

  defp fixtures do
    {:ok, teacher} = Catalog.create_teacher(%{name: "T", active: true})
    {:ok, student} = Teaching.create_student(%{first_name: "S", status: "prospective"})
    %{teacher: teacher, student: student}
  end

  defp lesson_attrs(%{teacher: t, student: s}, start_h) do
    %{
      scheduled_start: DateTime.new!(~D[2026-09-10], Time.new!(start_h, 0, 0), "Etc/UTC"),
      scheduled_end: DateTime.new!(~D[2026-09-10], Time.new!(start_h + 1, 0, 0), "Etc/UTC"),
      duration_minutes: 60,
      status: :scheduled,
      teacher_id: t.id,
      student_id: s.id,
      booking_token: "tok-#{start_h}"
    }
  end

  test "overlapping scheduled lessons for a teacher are rejected by the constraint" do
    f = fixtures()
    assert {:ok, _} = %Lesson{} |> Lesson.changeset(lesson_attrs(f, 15)) |> Repo.insert()

    {:error, changeset} =
      %Lesson{}
      |> Lesson.changeset(%{lesson_attrs(f, 15) | booking_token: "tok-dupe"})
      |> Repo.insert()

    assert "is already booked" in errors_on(changeset).scheduled_start
  end

  test "non-overlapping lessons both insert" do
    f = fixtures()
    assert {:ok, _} = %Lesson{} |> Lesson.changeset(lesson_attrs(f, 15)) |> Repo.insert()
    assert {:ok, _} = %Lesson{} |> Lesson.changeset(lesson_attrs(f, 16)) |> Repo.insert()
  end
end
