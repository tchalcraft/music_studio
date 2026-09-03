defmodule MusicStudio.Billing.StripeTest do
  # async: false — these tests mutate the global :stripe application env.
  use ExUnit.Case, async: false

  alias MusicStudio.Billing.Invoice
  alias MusicStudio.Billing.Stripe

  @webhook_secret "whsec_test_dummy"

  describe "health_check/0" do
    setup do
      original = Application.get_env(:music_studio, :stripe)
      on_exit(fn -> Application.put_env(:music_studio, :stripe, original) end)
      {:ok, original: original || []}
    end

    test "returns {:error, :missing_secret_key} when no key is configured", %{original: original} do
      Application.put_env(:music_studio, :stripe, Keyword.put(original, :secret_key, nil))
      assert {:error, :missing_secret_key} = Stripe.health_check()
    end

    test "treats a blank secret key as missing", %{original: original} do
      Application.put_env(:music_studio, :stripe, Keyword.put(original, :secret_key, ""))
      assert {:error, :missing_secret_key} = Stripe.health_check()
    end
  end

  describe "create_checkout_session/2" do
    test "posts a Checkout Session with Stripe Tax and returns {id, url}" do
      invoice = %Invoice{id: Ecto.UUID.generate(), currency: "CAD", subtotal_cents: 6000}

      Req.Test.stub(Stripe, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = URI.decode(body)

        assert conn.method == "POST"
        assert conn.request_path == "/v1/checkout/sessions"
        assert decoded =~ "mode=payment"
        assert decoded =~ "line_items[0][price_data][unit_amount]=6000"
        assert decoded =~ "client_reference_id=#{invoice.id}"
        # Stripe Tax is intentionally not enabled.
        refute decoded =~ "automatic_tax"
        refute decoded =~ "tax_behavior"

        Req.Test.json(conn, %{
          "id" => "cs_test_123",
          "url" => "https://checkout.stripe.com/c/pay/cs_test_123"
        })
      end)

      assert {:ok, %{id: "cs_test_123", url: "https://checkout.stripe.com/c/pay/cs_test_123"}} =
               Stripe.create_checkout_session(invoice,
                 success_url: "https://x/success",
                 cancel_url: "https://x/cancel"
               )
    end

    test "surfaces a Stripe API error" do
      invoice = %Invoice{id: Ecto.UUID.generate(), currency: "CAD", subtotal_cents: 6000}

      Req.Test.stub(Stripe, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => %{"message" => "No such customer"}})
      end)

      assert {:error, {:stripe_error, 400, "No such customer"}} =
               Stripe.create_checkout_session(invoice,
                 success_url: "https://x/success",
                 cancel_url: "https://x/cancel"
               )
    end
  end

  describe "construct_event/2" do
    test "accepts a valid signature and decodes the event" do
      payload = ~s({"type":"checkout.session.completed","id":"evt_1"})
      header = sign(payload, System.system_time(:second))

      assert {:ok, %{"type" => "checkout.session.completed", "id" => "evt_1"}} =
               Stripe.construct_event(payload, header)
    end

    test "rejects a tampered payload" do
      payload = ~s({"type":"checkout.session.completed"})
      header = sign(payload, System.system_time(:second))

      assert {:error, :signature_mismatch} =
               Stripe.construct_event(payload <> " ", header)
    end

    test "rejects a stale timestamp" do
      payload = ~s({"type":"checkout.session.completed"})
      header = sign(payload, System.system_time(:second) - 10_000)

      assert {:error, :timestamp_out_of_tolerance} = Stripe.construct_event(payload, header)
    end

    test "rejects a malformed signature header" do
      assert {:error, :invalid_signature_header} =
               Stripe.construct_event(~s({}), "not-a-real-header")
    end
  end

  # Mirror Stripe's signing scheme so tests build valid Stripe-Signature headers.
  defp sign(payload, timestamp) do
    signature =
      :hmac
      |> :crypto.mac(:sha256, @webhook_secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{signature}"
  end
end
