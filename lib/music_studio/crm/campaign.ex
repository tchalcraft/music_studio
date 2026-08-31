defmodule MusicStudio.CRM.Campaign do
  @moduledoc "A marketing campaign that drives touchpoints/inquiries."
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.CRM.Touchpoint

  @channels [:email, :social, :referral, :search, :other]

  schema "campaigns" do
    field :name, :string
    field :channel, Ecto.Enum, values: @channels, default: :other
    field :started_on, :date
    field :ended_on, :date
    field :deleted_at, :utc_datetime_usec

    has_many :touchpoints, Touchpoint

    timestamps()
  end

  @doc "Allowed campaign channels."
  def channels, do: @channels

  @doc false
  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [:name, :channel, :started_on, :ended_on, :deleted_at])
    |> validate_required([:name, :channel])
    |> validate_length(:name, min: 1, max: 200)
  end
end
