defmodule MusicStudio.Scheduling.GoogleAuth do
  @moduledoc """
  Mints Google API access tokens from a service-account key via the JWT-bearer grant
  (RS256, signed with pure OTP `:public_key` — no extra dependency). Scope covers reading
  the Availability calendar and writing lesson events. Replaces the former OAuth flow.
  """
  @scope "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly"

  @spec mint_access_token() :: {:ok, map()} | {:error, term()}
  def mint_access_token do
    key = cfg(:service_account_key) || %{}
    token_uri = key["token_uri"] || cfg(:google_token_url)

    with {:ok, jwt} <- signed_jwt(key, token_uri) do
      form = %{
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => jwt
      }

      case Req.post(req(url: token_uri, form: form)) do
        {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
          {:ok,
           %{
             access_token: token,
             expires_at: DateTime.add(DateTime.utc_now(), body["expires_in"] || 3600, :second)
           }}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp signed_jwt(%{"client_email" => iss, "private_key" => pem}, aud)
       when is_binary(iss) and is_binary(pem) do
    now = System.system_time(:second)
    header = %{"alg" => "RS256", "typ" => "JWT"}
    claims = %{"iss" => iss, "scope" => @scope, "aud" => aud, "iat" => now, "exp" => now + 3600}

    signing_input = b64(Jason.encode!(header)) <> "." <> b64(Jason.encode!(claims))
    signature = :public_key.sign(signing_input, :sha256, private_key(pem))
    {:ok, signing_input <> "." <> b64(signature)}
  end

  defp signed_jwt(_key, _aud), do: {:error, :missing_service_account_key}

  defp private_key(pem) do
    [entry] = :public_key.pem_decode(pem)
    :public_key.pem_entry_decode(entry)
  end

  defp b64(bin), do: Base.url_encode64(bin, padding: false)

  @doc false
  def req(opts) do
    Req.new(opts) |> Req.merge(Application.get_env(:music_studio, :scheduling_req_options, []))
  end

  defp cfg(key),
    do: Keyword.get(Application.get_env(:music_studio, MusicStudio.Scheduling, []), key)
end
