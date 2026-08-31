defmodule MusicStudio.Teaching.Guardian do
  @moduledoc "A parent/guardian or billing payer, typically for a minor student."
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Teaching.Student

  schema "guardians" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :phone, :string
    field :deleted_at, :utc_datetime_usec

    has_many :students, Student

    timestamps()
  end

  @doc false
  def changeset(guardian, attrs) do
    guardian
    |> cast(attrs, [:first_name, :last_name, :email, :phone, :deleted_at])
    |> validate_required([:first_name, :last_name])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
  end
end
