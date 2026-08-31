defmodule MusicStudio.Teaching do
  @moduledoc """
  The teaching domain: people (guardians, students) and activity (enrollments, lessons).
  Students may link back to a `Lead` (funnel). List functions exclude soft-deleted rows.
  """
  import Ecto.Query, warn: false

  alias MusicStudio.Repo
  alias MusicStudio.Teaching.Enrollment
  alias MusicStudio.Teaching.Guardian
  alias MusicStudio.Teaching.Lesson
  alias MusicStudio.Teaching.Student

  ## Guardians

  def list_guardians, do: Repo.all(active_scope(Guardian))
  def get_guardian!(id), do: Repo.get!(Guardian, id)

  def change_guardian(%Guardian{} = g \\ %Guardian{}, attrs \\ %{}),
    do: Guardian.changeset(g, attrs)

  def create_guardian(attrs \\ %{}),
    do: %Guardian{} |> Guardian.changeset(attrs) |> Repo.insert()

  def update_guardian(%Guardian{} = g, attrs),
    do: g |> Guardian.changeset(attrs) |> Repo.update()

  ## Students

  def list_students, do: Repo.all(active_scope(Student))
  def get_student!(id), do: Repo.get!(Student, id)

  def change_student(%Student{} = s \\ %Student{}, attrs \\ %{}),
    do: Student.changeset(s, attrs)

  def create_student(attrs \\ %{}),
    do: %Student{} |> Student.changeset(attrs) |> Repo.insert()

  def update_student(%Student{} = s, attrs),
    do: s |> Student.changeset(attrs) |> Repo.update()

  ## Enrollments

  def list_enrollments, do: Repo.all(active_scope(Enrollment))
  def get_enrollment!(id), do: Repo.get!(Enrollment, id)

  def change_enrollment(%Enrollment{} = e \\ %Enrollment{}, attrs \\ %{}),
    do: Enrollment.changeset(e, attrs)

  def create_enrollment(attrs \\ %{}),
    do: %Enrollment{} |> Enrollment.changeset(attrs) |> Repo.insert()

  def update_enrollment(%Enrollment{} = e, attrs),
    do: e |> Enrollment.changeset(attrs) |> Repo.update()

  ## Lessons

  def list_lessons,
    do: Repo.all(from l in active_scope(Lesson), order_by: [desc: l.scheduled_start])

  def get_lesson!(id), do: Repo.get!(Lesson, id)

  def change_lesson(%Lesson{} = l \\ %Lesson{}, attrs \\ %{}), do: Lesson.changeset(l, attrs)

  def create_lesson(attrs \\ %{}), do: %Lesson{} |> Lesson.changeset(attrs) |> Repo.insert()

  def update_lesson(%Lesson{} = l, attrs), do: l |> Lesson.changeset(attrs) |> Repo.update()

  defp active_scope(queryable), do: from(r in queryable, where: is_nil(r.deleted_at))
end
