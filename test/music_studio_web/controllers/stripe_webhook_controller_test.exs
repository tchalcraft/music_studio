defmodule MusicStudioWeb.StripeWebhookControllerTest do
  use MusicStudioWeb.ConnCase

  alias MusicStudio.Billing

  @webhook_secret "whsec_test_dummy"

  defp create_invoice do
    {:ok, invoice} =
      Billing.create_invoice(%{
        status: :open,
        currency: "CAD",
        subtotal_cents: 6000,
        total_cents: 6000,
        issued_on: Date.utc_today()
      })

    invoice
  end

  defp completed_event(invoice) do
    Jason.encode!(%{
      "type" => "checkout.session.completed",
      "data" => %{
        "object" => %{
          "id" => "cs_test_webhook_#{System.unique_integer([:positive])}",
          "client_reference_id" => invoice.id,
          "amount_total" => 6000,
          "currency" => "cad",
          "payment_intent" => "pi_webhook_1",
          "total_details" => %{"amount_tax" => 0}
        }
      }
    })
  end

  defp post_webhook(conn, payload, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> post(~p"/webhooks/stripe", payload)
  end

  defp sign(payload, timestamp \\ System.system_time(:second)) do
    hmac =
      :hmac
      |> :crypto.mac(:sha256, @webhook_secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{hmac}"
  end

  test "a verified checkout.session.completed fulfills the invoice and returns 200", %{conn: conn} do
    invoice = create_invoice()
    payload = completed_event(invoice)

    conn = post_webhook(conn, payload, sign(payload))

    assert response(conn, 200)
    assert Billing.get_invoice!(invoice.id).status == :paid
  end

  test "a bad signature returns 400 and does not fulfill", %{conn: conn} do
    invoice = create_invoice()
    payload = completed_event(invoice)

    # Fresh timestamp so it fails on the signature itself, not the replay window.
    bad_signature = "t=#{System.system_time(:second)},v1=deadbeef"
    conn = post_webhook(conn, payload, bad_signature)

    assert response(conn, 400)
    assert Billing.get_invoice!(invoice.id).status == :open
  end
end
