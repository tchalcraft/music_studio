defmodule MusicStudio.Catalog.Location do
  @moduledoc "Where lessons happen. Seeded with the in-person studio; `online` supported for the future."
  use MusicStudio.Schema
  import Ecto.Changeset

  @kinds [:in_person, :online]

  schema "locations" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds, default: :in_person
    field :address_line, :string
    field :city, :string
    field :region, :string
    field :postal_code, :string
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime_usec

    timestamps()
  end

  @doc "Allowed location kinds."
  def kinds, do: @kinds

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :name,
      :kind,
      :address_line,
      :city,
      :region,
      :postal_code,
      :active,
      :deleted_at
    ])
    |> validate_required([:name, :kind])
    |> validate_length(:name, min: 1, max: 200)
  end
end
