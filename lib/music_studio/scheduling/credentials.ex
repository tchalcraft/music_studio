defmodule MusicStudio.Scheduling.Credentials do
  @moduledoc """
  Hands out a currently-valid Google access token (minted from the service-account key)
  and the configured calendar ids. No stored refresh token / connect flow — the service
  account is authorized by sharing the calendar with it.
  """
  alias MusicStudio.Scheduling.GoogleAuth

  @spec fresh_access_token() :: {:ok, String.t()} | {:error, term()}
  def fresh_access_token do
    case GoogleAuth.mint_access_token() do
      {:ok, %{access_token: token}} -> {:ok, token}
      other -> other
    end
  end

  @spec configured?() :: boolean()
  def configured?, do: is_map(cfg(:service_account_key)) and is_binary(availability_calendar_id())

  @spec availability_calendar_id() :: String.t() | nil
  def availability_calendar_id, do: cfg(:availability_calendar_id)

  @spec target_calendar_id() :: String.t() | nil
  def target_calendar_id, do: cfg(:target_calendar_id) || cfg(:availability_calendar_id)

  defp cfg(key),
    do: Keyword.get(Application.get_env(:music_studio, MusicStudio.Scheduling, []), key)
end
