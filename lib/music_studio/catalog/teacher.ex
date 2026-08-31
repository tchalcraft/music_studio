defmodule MusicStudio.Catalog.Teacher do
  @moduledoc "A music teacher. Modeled generically (multi-teacher-ready); seeded with Tristan."
  use MusicStudio.Schema
  import Ecto.Changeset

  schema "teachers" do
    field :name, :string
    field :email, :string
    field :bio, :string
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(teacher, attrs) do
    teacher
    |> cast(attrs, [:name, :email, :bio, :active, :deleted_at])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
  end
end
