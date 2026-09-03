defmodule MusicStudio.Billing.Stripe do
  @moduledoc """
  Thin Stripe API client for the Billing context.

  Credentials come from configuration, never from code:
  `config :music_studio, :stripe, secret_key: ..., webhook_secret: ...`. In production the
  keys are read from `STRIPE_*` env vars (see `config/runtime.exs`); locally they are set
  in `config/dev.secret.exs` from the `STRIPE_*` exports in the project-root `.envrc`.

  Covers the pieces the pay-an-invoice flow needs:

    * `health_check/0` — confirm the secret key reaches Stripe.
    * `create_checkout_session/2` — open a hosted Checkout Session for an invoice.
    * `construct_event/2` — verify a webhook's `Stripe-Signature` and decode its payload.
  """

  alias MusicStudio.Billing.Invoice

  @default_base_url "https://api.stripe.com"

  # Reject webhook signatures whose timestamp is more than this far from now (replay guard).
  @signature_tolerance_seconds 300

  @doc """
  Confirms the configured secret key reaches Stripe.

  Calls `GET /v1/account` and returns `{:ok, account_id}` on success, or
  `{:error, reason}` if the key is missing, rejected, or the request fails.
  """
  @spec health_check() :: {:ok, String.t()} | {:error, term()}
  def health_check do
    with {:ok, secret_key} <- fetch_secret_key() do
      case request(method: :get, url: "/v1/account", auth: {:bearer, secret_key}) do
        {:ok, %{status: 200, body: %{"id" => account_id}}} ->
          {:ok, account_id}

        {:ok, %{status: status, body: body}} ->
          {:error, {:stripe_error, status, error_message(body)}}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @doc """
  Creates a Stripe Checkout Session to pay `invoice`.

  `mode: payment` for a single line item covering the invoice subtotal. The invoice id
  travels in both `client_reference_id` and `metadata[invoice_id]` so the webhook can
  reconcile the payment. (No tax is collected — Stripe Tax is intentionally not enabled.)

  Required `opts`: `:success_url`, `:cancel_url`.

  Returns `{:ok, %{id: session_id, url: hosted_url}}` or `{:error, reason}`.
  """
  @spec create_checkout_session(Invoice.t(), keyword()) ::
          {:ok, %{id: String.t(), url: String.t()}} | {:error, term()}
  def create_checkout_session(%Invoice{} = invoice, opts) do
    with {:ok, secret_key} <- fetch_secret_key() do
      form = checkout_params(invoice, opts)

      case request(
             method: :post,
             url: "/v1/checkout/sessions",
             auth: {:bearer, secret_key},
             form: form
           ) do
        {:ok, %{status: 200, body: %{"id" => id, "url" => url}}} ->
          {:ok, %{id: id, url: url}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:stripe_error, status, error_message(body)}}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  @doc """
  Verifies a webhook request and decodes its event.

  Checks the `Stripe-Signature` header against the raw request `payload` using the
  configured `:webhook_secret` (HMAC-SHA256, constant-time compare, timestamp within
  #{@signature_tolerance_seconds}s). Returns `{:ok, event_map}` on success or
  `{:error, reason}` — `:missing_webhook_secret`, `:invalid_signature_header`,
  `:timestamp_out_of_tolerance`, or `:signature_mismatch`.
  """
  @spec construct_event(binary(), binary()) :: {:ok, map()} | {:error, atom()}
  def construct_event(payload, sig_header)
      when is_binary(payload) and is_binary(sig_header) do
    with {:ok, secret} <- fetch_webhook_secret(),
         {:ok, timestamp, signatures} <- parse_signature_header(sig_header),
         :ok <- check_timestamp(timestamp),
         :ok <- verify_signature(payload, timestamp, signatures, secret) do
      {:ok, Jason.decode!(payload)}
    end
  end

  def construct_event(_payload, _sig_header), do: {:error, :invalid_signature_header}

  ## Checkout params

  defp checkout_params(%Invoice{} = invoice, opts) do
    success_url = Keyword.fetch!(opts, :success_url)
    cancel_url = Keyword.fetch!(opts, :cancel_url)
    currency = String.downcase(invoice.currency || "cad")

    [
      {"mode", "payment"},
      {"success_url", success_url},
      {"cancel_url", cancel_url},
      {"client_reference_id", invoice.id},
      {"metadata[invoice_id]", invoice.id},
      {"line_items[0][quantity]", "1"},
      {"line_items[0][price_data][currency]", currency},
      {"line_items[0][price_data][unit_amount]", invoice.subtotal_cents},
      {"line_items[0][price_data][product_data][name]", line_item_name(invoice)}
    ]
  end

  defp line_item_name(%Invoice{id: id}) do
    "Invoice #{id |> to_string() |> String.slice(0, 8)}"
  end

  ## Signature verification

  defp parse_signature_header(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "=", parts: 2))

    timestamp =
      Enum.find_value(parts, fn
        ["t", value] -> value
        _ -> nil
      end)

    signatures = for ["v1", value] <- parts, do: value

    case {parse_integer(timestamp), signatures} do
      {{:ok, ts}, [_ | _]} -> {:ok, ts, signatures}
      _ -> {:error, :invalid_signature_header}
    end
  end

  defp check_timestamp(timestamp) do
    if abs(System.system_time(:second) - timestamp) <= @signature_tolerance_seconds do
      :ok
    else
      {:error, :timestamp_out_of_tolerance}
    end
  end

  defp verify_signature(payload, timestamp, signatures, secret) do
    expected =
      :hmac
      |> :crypto.mac(:sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    if Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)) do
      :ok
    else
      {:error, :signature_mismatch}
    end
  end

  defp parse_integer(nil), do: :error

  defp parse_integer(string) do
    case Integer.parse(string) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  ## HTTP + config

  defp request(opts) do
    base_url = Keyword.get(config(), :api_base_url) || @default_base_url

    [base_url: base_url]
    |> Keyword.merge(req_plug())
    |> Keyword.merge(opts)
    |> Req.request()
  end

  # In tests `:req_plug` points requests at a `Req.Test` stub instead of the network.
  defp req_plug do
    case Keyword.get(config(), :req_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end

  defp fetch_secret_key do
    case Keyword.get(config(), :secret_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_secret_key}
    end
  end

  defp fetch_webhook_secret do
    case Keyword.get(config(), :webhook_secret) do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _ -> {:error, :missing_webhook_secret}
    end
  end

  defp config, do: Application.get_env(:music_studio, :stripe, [])

  defp error_message(%{"error" => %{"message" => message}}), do: message
  defp error_message(_), do: "unknown error"
end
