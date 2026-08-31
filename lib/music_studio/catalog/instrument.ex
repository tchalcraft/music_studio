defmodule MusicStudio.Catalog.Instrument do
  @moduledoc "An instrument/subject taught. Seeded with voice, piano, guitar."
  use MusicStudio.Schema
  import Ecto.Changeset

  schema "instruments" do
    field :name, :string
    field :slug, :string
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(instrument, attrs) do
    instrument
    |> cast(attrs, [:name, :slug, :active, :deleted_at])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &(&1 |> String.trim() |> String.downcase()))
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase letters, digits, or hyphens"
    )
    |> unique_constraint(:slug)
  end
end
