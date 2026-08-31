defmodule MusicStudio.Teaching.Student do
  @moduledoc """
  A student. May belong to a guardian (payer) and may have originated from a `Lead`
  (the funnel link — `lead_id` is a bigint FK, since the leads table predates the UUIDv7
  model).
  """
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Teaching.Guardian

  @statuses [:prospective, :active, :paused, :inactive]

  schema "students" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :phone, :string
    field :date_of_birth, :date
    field :status, Ecto.Enum, values: @statuses, default: :prospective
    field :notes, :string
    # FK to the pre-existing bigint `leads` table (funnel origin). Not a UUIDv7 assoc.
    field :lead_id, :integer
    field :deleted_at, :utc_datetime_usec

    belongs_to :guardian, Guardian

    timestamps()
  end

  @doc "Allowed student statuses."
  def statuses, do: @statuses

  @doc false
  def changeset(student, attrs) do
    student
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :phone,
      :date_of_birth,
      :status,
      :notes,
      :lead_id,
      :guardian_id,
      :deleted_at
    ])
    |> validate_required([:first_name, :status])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> assoc_constraint(:guardian)
  end
end
