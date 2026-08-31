defmodule MusicStudio.Teaching.Lesson do
  @moduledoc """
  A single lesson/session — the core activity fact. Carries a price snapshot and an
  attendance-bearing status. Denormalized FKs (student/teacher/instrument) alongside the
  enrollment make it a convenient grain for analytics.
  """
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Catalog.Instrument
  alias MusicStudio.Catalog.Location
  alias MusicStudio.Catalog.Offering
  alias MusicStudio.Catalog.Teacher
  alias MusicStudio.Teaching.Enrollment
  alias MusicStudio.Teaching.Student

  @statuses [:scheduled, :completed, :cancelled, :no_show, :rescheduled]

  schema "lessons" do
    field :scheduled_start, :utc_datetime
    field :scheduled_end, :utc_datetime
    field :duration_minutes, :integer
    field :status, Ecto.Enum, values: @statuses, default: :scheduled
    field :price_cents, :integer
    field :currency, :string, default: "CAD"
    field :notes, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :enrollment, Enrollment
    belongs_to :student, Student
    belongs_to :teacher, Teacher
    belongs_to :instrument, Instrument
    belongs_to :offering, Offering
    belongs_to :location, Location

    timestamps()
  end

  @doc "Allowed lesson statuses (includes attendance outcomes)."
  def statuses, do: @statuses

  @doc false
  def changeset(lesson, attrs) do
    lesson
    |> cast(attrs, [
      :scheduled_start,
      :scheduled_end,
      :duration_minutes,
      :status,
      :price_cents,
      :currency,
      :notes,
      :deleted_at,
      :enrollment_id,
      :student_id,
      :teacher_id,
      :instrument_id,
      :offering_id,
      :location_id
    ])
    |> validate_required([:scheduled_start, :status, :student_id, :teacher_id])
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:enrollment)
    |> assoc_constraint(:student)
    |> assoc_constraint(:teacher)
    |> assoc_constraint(:instrument)
    |> assoc_constraint(:offering)
    |> assoc_constraint(:location)
  end
end
