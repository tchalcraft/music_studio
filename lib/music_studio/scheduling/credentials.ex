defmodule MusicStudio.Scheduling.Credentials do
  @moduledoc """
  Read/write the single stored Google credential and hand out a currently-valid access
  token, refreshing (and persisting the new token) when the cached one is near expiry.
  """
  alias MusicStudio.Repo
  alias MusicStudio.Scheduling.{Credential, GoogleAuth}

  @provider "google"

  @spec get() :: Credential.t() | nil
  def get, do: Repo.get_by(Credential, provider: @provider)

  @spec upsert(map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def upsert(attrs) do
    attrs = Map.put(attrs, :provider, @provider)

    case get() do
      nil -> %Credential{}
      cred -> cred
    end
    |> Credential.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec fresh_access_token() :: {:ok, String.t()} | {:error, term()}
  def fresh_access_token do
    case get() do
      nil -> {:error, :not_connected}
      %Credential{refresh_token: nil} -> {:error, :not_connected}
      cred -> ensure_token(cred)
    end
  end

  defp ensure_token(cred) do
    if valid?(cred.access_token, cred.access_token_expires_at) do
      {:ok, cred.access_token}
    else
      with {:ok, %{access_token: token, expires_at: exp}} <-
             GoogleAuth.refresh(cred.refresh_token),
           {:ok, _} <- upsert(%{access_token: token, access_token_expires_at: exp}) do
        {:ok, token}
      end
    end
  end

  defp valid?(nil, _), do: false
  defp valid?(_token, nil), do: false

  defp valid?(_token, expires_at) do
    DateTime.compare(expires_at, DateTime.add(DateTime.utc_now(), 60, :second)) == :gt
  end
end
