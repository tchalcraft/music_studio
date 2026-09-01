defmodule MusicStudio.Scheduling.Credential do
  @moduledoc """
  Stored OAuth credential for a calendar provider (one row per provider, e.g. "google").
  Holds the long-lived refresh token plus a cached access token and the two calendar ids
  chosen during the connect flow.
  """
  use MusicStudio.Schema
  import Ecto.Changeset

  schema "scheduling_credentials" do
    field :provider, :string, default: "google"
    field :refresh_token, :string
    field :access_token, :string
    field :access_token_expires_at, :utc_datetime_usec
    field :availability_calendar_id, :string
    field :target_calendar_id, :string

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :provider,
      :refresh_token,
      :access_token,
      :access_token_expires_at,
      :availability_calendar_id,
      :target_calendar_id
    ])
    |> validate_required([:provider])
    |> unique_constraint(:provider)
  end
end
