defmodule MusicStudio.Teaching.Enrollment do
  @moduledoc "An ongoing student↔instrument↔teacher relationship, with a default offering/location."
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Catalog.Instrument
  alias MusicStudio.Catalog.Location
  alias MusicStudio.Catalog.Offering
  alias MusicStudio.Catalog.Teacher
  alias MusicStudio.Teaching.Student

  @statuses [:active, :paused, :completed, :cancelled]

  schema "enrollments" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_on, :date
    field :ended_on, :date
    field :deleted_at, :utc_datetime_usec

    belongs_to :student, Student
    belongs_to :teacher, Teacher
    belongs_to :instrument, Instrument
    belongs_to :offering, Offering
    belongs_to :location, Location

    timestamps()
  end

  @doc "Allowed enrollment statuses."
  def statuses, do: @statuses

  @doc false
  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [
      :status,
      :started_on,
      :ended_on,
      :deleted_at,
      :student_id,
      :teacher_id,
      :instrument_id,
      :offering_id,
      :location_id
    ])
    |> validate_required([:status, :student_id, :teacher_id, :instrument_id])
    |> assoc_constraint(:student)
    |> assoc_constraint(:teacher)
    |> assoc_constraint(:instrument)
    |> assoc_constraint(:offering)
    |> assoc_constraint(:location)
  end
end
