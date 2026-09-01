defmodule MusicStudio.Scheduling.GoogleAuth do
  @moduledoc """
  Google OAuth 2.0 authorization-code helpers (hand-rolled over `Req`): build the consent
  URL, exchange an auth code for tokens, and refresh an access token. The scope covers
  reading the Availability calendar's events and writing booked lesson events.
  """
  @scope "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly"

  @spec authorize_url(String.t()) :: String.t()
  def authorize_url(state) do
    query =
      URI.encode_query(%{
        "client_id" => cfg(:google_client_id),
        "redirect_uri" => cfg(:google_redirect_uri),
        "response_type" => "code",
        "scope" => @scope,
        "access_type" => "offline",
        "prompt" => "consent",
        "state" => state
      })

    cfg(:google_auth_url) <> "?" <> query
  end

  @spec exchange_code(String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_code(code) do
    post_token(%{
      "code" => code,
      "client_id" => cfg(:google_client_id),
      "client_secret" => cfg(:google_client_secret),
      "redirect_uri" => cfg(:google_redirect_uri),
      "grant_type" => "authorization_code"
    })
    |> case do
      {:ok, %{"refresh_token" => _} = body} -> {:ok, to_tokens(body)}
      {:ok, body} -> {:error, {:no_refresh_token, body}}
      other -> other
    end
  end

  @spec refresh(String.t()) :: {:ok, map()} | {:error, term()}
  def refresh(refresh_token) do
    post_token(%{
      "client_id" => cfg(:google_client_id),
      "client_secret" => cfg(:google_client_secret),
      "refresh_token" => refresh_token,
      "grant_type" => "refresh_token"
    })
    |> case do
      {:ok, body} -> {:ok, Map.take(to_tokens(body), [:access_token, :expires_at])}
      other -> other
    end
  end

  defp post_token(form) do
    case Req.post(req(url: cfg(:google_token_url), form: form)) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_tokens(body) do
    %{
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      expires_at: DateTime.add(DateTime.utc_now(), body["expires_in"] || 3600, :second)
    }
  end

  @doc false
  def req(opts) do
    Req.new(opts)
    |> Req.merge(Application.get_env(:music_studio, :scheduling_req_options, []))
  end

  defp cfg(key),
    do: Keyword.fetch!(Application.get_env(:music_studio, MusicStudio.Scheduling), key)
end
