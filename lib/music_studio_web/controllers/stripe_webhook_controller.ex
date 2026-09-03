defmodule MusicStudioWeb.StripeWebhookController do
  @moduledoc """
  Receives Stripe webhooks at `POST /webhooks/stripe`.

  Verifies the `Stripe-Signature` against the raw request body (cached by
  `MusicStudioWeb.CacheBodyReader`), then fulfills `checkout.session.completed` events.
  Returns 400 on a bad signature; 200 once an event is verified (so Stripe stops
  retrying), except transient fulfillment failures, which return 500 so Stripe retries.
  """
  use MusicStudioWeb, :controller

  require Logger

  alias MusicStudio.Billing.Checkout
  alias MusicStudio.Billing.Stripe

  # Permanent problems: retrying won't help, so ack with 200 (but log loudly).
  @permanent_errors [:invoice_not_found, :missing_invoice_reference, :missing_session_id]

  def handle(conn, _params) do
    payload = raw_body(conn)
    signature = conn |> get_req_header("stripe-signature") |> List.first() || ""

    case Stripe.construct_event(payload, signature) do
      {:ok, %{"type" => "checkout.session.completed", "data" => %{"object" => session}}} ->
        fulfill(conn, session)

      {:ok, %{"type" => type}} ->
        Logger.debug("Stripe webhook: ignoring event type #{type}")
        send_resp(conn, 200, "ignored")

      {:error, reason} ->
        Logger.warning("Stripe webhook rejected: #{inspect(reason)}")
        send_resp(conn, 400, "invalid signature")
    end
  end

  defp fulfill(conn, session) do
    case Checkout.fulfill_session(session) do
      {:ok, _result} ->
        send_resp(conn, 200, "ok")

      {:error, reason} when reason in @permanent_errors ->
        Logger.error("Stripe fulfillment skipped (#{inspect(reason)}): session #{session["id"]}")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.error("Stripe fulfillment failed (#{inspect(reason)}): session #{session["id"]}")
        send_resp(conn, 500, "error")
    end
  end

  # The raw body is cached as an iodata list (see CacheBodyReader) so signature
  # verification sees the exact bytes Stripe signed.
  defp raw_body(conn) do
    conn.assigns
    |> Map.get(:raw_body, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end
end
