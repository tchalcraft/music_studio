defmodule MusicStudio.Billing.Stripe do
  @moduledoc """
  Thin Stripe API client for the Billing context.

  Credentials come from configuration, never from code:
  `config :music_studio, :stripe, secret_key: ...`. In production the key is read from
  the `STRIPE_SECRET_KEY` env var (see `config/runtime.exs`); locally it is set in
  `config/dev.secret.exs` from the `STRIPE_*` exports in the project-root `.envrc`.

  Only `health_check/0` exists so far — enough to confirm the keys are wired end to end.
  The actual payment flow (Stripe Checkout + Stripe Tax) is a later phase.
  """

  @default_base_url "https://api.stripe.com"

  @doc """
  Confirms the configured secret key reaches Stripe.

  Calls `GET /v1/account` and returns `{:ok, account_id}` on success, or
  `{:error, reason}` if the key is missing, rejected, or the request fails.
  """
  @spec health_check() :: {:ok, String.t()} | {:error, term()}
  def health_check do
    with {:ok, secret_key} <- fetch_secret_key() do
      case request(url: "/v1/account", auth: {:bearer, secret_key}) do
        {:ok, %{status: 200, body: %{"id" => account_id}}} ->
          {:ok, account_id}

        {:ok, %{status: status, body: body}} ->
          {:error, {:stripe_error, status, error_message(body)}}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  defp request(opts) do
    base_url = Keyword.get(config(), :api_base_url) || @default_base_url

    [method: :get, base_url: base_url]
    |> Keyword.merge(opts)
    |> Req.request()
  end

  defp fetch_secret_key do
    case Keyword.get(config(), :secret_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_secret_key}
    end
  end

  defp config, do: Application.get_env(:music_studio, :stripe, [])

  defp error_message(%{"error" => %{"message" => message}}), do: message
  defp error_message(_), do: "unknown error"
end
