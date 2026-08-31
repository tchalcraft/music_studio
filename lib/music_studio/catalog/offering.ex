defmodule MusicStudio.Catalog.Offering do
  @moduledoc """
  A bookable lesson type: a duration at a price (the rate card — 60/45/30 min).
  `instrument_id` is optional, leaving room for per-instrument pricing later.
  """
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Catalog.Instrument

  schema "offerings" do
    field :name, :string
    field :duration_minutes, :integer
    field :price_cents, :integer
    field :currency, :string, default: "CAD"
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime_usec

    belongs_to :instrument, Instrument

    timestamps()
  end

  @doc false
  def changeset(offering, attrs) do
    offering
    |> cast(attrs, [
      :name,
      :duration_minutes,
      :price_cents,
      :currency,
      :active,
      :deleted_at,
      :instrument_id
    ])
    |> validate_required([:name, :duration_minutes, :price_cents, :currency])
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> assoc_constraint(:instrument)
  end
end
