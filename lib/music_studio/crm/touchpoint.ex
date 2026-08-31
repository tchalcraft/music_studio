defmodule MusicStudio.CRM.Touchpoint do
  @moduledoc """
  A CRM interaction with a lead or student (email, call, referral, etc.), optionally
  attributed to a campaign. `lead_id` is a bigint FK (the leads table predates UUIDv7).
  """
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.CRM.Campaign
  alias MusicStudio.Teaching.Student

  @channels [:email, :phone, :sms, :social, :in_person, :referral, :other]
  @directions [:inbound, :outbound]

  schema "touchpoints" do
    field :channel, Ecto.Enum, values: @channels, default: :email
    field :direction, Ecto.Enum, values: @directions, default: :outbound
    field :occurred_at, :utc_datetime_usec
    field :summary, :string
    field :metadata, :map, default: %{}
    # FK to the pre-existing bigint `leads` table.
    field :lead_id, :integer

    belongs_to :student, Student
    belongs_to :campaign, Campaign

    timestamps()
  end

  @doc "Allowed touchpoint channels."
  def channels, do: @channels

  @doc "Allowed touchpoint directions."
  def directions, do: @directions

  @doc false
  def changeset(touchpoint, attrs) do
    touchpoint
    |> cast(attrs, [
      :channel,
      :direction,
      :occurred_at,
      :summary,
      :metadata,
      :lead_id,
      :student_id,
      :campaign_id
    ])
    |> validate_required([:channel, :direction, :occurred_at])
    |> assoc_constraint(:student)
    |> assoc_constraint(:campaign)
  end
end
