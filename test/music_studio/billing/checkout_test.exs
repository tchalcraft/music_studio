defmodule MusicStudio.Billing.CheckoutTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Analytics
  alias MusicStudio.Billing
  alias MusicStudio.Billing.Checkout
  alias MusicStudio.Billing.Payment
  alias MusicStudio.Teaching

  defp open_invoice(_ctx) do
    {:ok, guardian} = Teaching.create_guardian(%{first_name: "Pat", last_name: "Payer"})

    {:ok, invoice} =
      Billing.create_invoice(%{
        guardian_id: guardian.id,
        status: :open,
        currency: "CAD",
        subtotal_cents: 6000,
        total_cents: 6000,
        issued_on: Date.utc_today()
      })

    %{guardian: guardian, invoice: invoice}
  end

  defp session_for(invoice, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "cs_test_#{System.unique_integer([:positive])}",
        "client_reference_id" => invoice.id,
        "amount_total" => 6000,
        "currency" => "cad",
        "payment_intent" => "pi_test_1",
        "total_details" => %{"amount_tax" => 0}
      },
      overrides
    )
  end

  describe "fulfill_session/1" do
    setup :open_invoice

    test "records a Stripe payment and marks the invoice paid", %{invoice: invoice} do
      session = session_for(invoice)

      assert {:ok, %Payment{} = payment} = Checkout.fulfill_session(session)
      assert payment.method == :stripe
      assert payment.amount_cents == 6000
      assert payment.currency == "CAD"
      assert payment.stripe_checkout_session_id == session["id"]
      assert payment.stripe_payment_intent_id == "pi_test_1"
      assert payment.reference == "pi_test_1"

      reloaded = Billing.get_invoice!(invoice.id)
      assert reloaded.status == :paid
      assert reloaded.tax_cents == 0
      assert reloaded.total_cents == 6000
    end

    test "records an analytics event", %{invoice: invoice} do
      assert {:ok, _payment} = Checkout.fulfill_session(session_for(invoice))

      assert [event] = Analytics.list_events_for("invoice", invoice.id)
      assert event.verb == "invoice_paid"
      assert event.metadata["method"] == "stripe"
    end

    test "is idempotent on the checkout session id", %{invoice: invoice} do
      session = session_for(invoice)

      assert {:ok, %Payment{}} = Checkout.fulfill_session(session)
      assert {:ok, :already_fulfilled} = Checkout.fulfill_session(session)

      assert length(Billing.list_payments()) == 1
    end

    test "falls back to metadata[invoice_id] when client_reference_id is absent", %{
      invoice: invoice
    } do
      session =
        session_for(invoice, %{
          "client_reference_id" => nil,
          "metadata" => %{"invoice_id" => invoice.id}
        })

      assert {:ok, %Payment{}} = Checkout.fulfill_session(session)
      assert Billing.get_invoice!(invoice.id).status == :paid
    end
  end

  describe "fulfill_session/1 error paths" do
    test "returns :invoice_not_found for an unknown invoice" do
      session = %{
        "id" => "cs_test_missing",
        "client_reference_id" => Ecto.UUID.generate(),
        "amount_total" => 1000,
        "currency" => "cad",
        "payment_intent" => "pi_x",
        "total_details" => %{"amount_tax" => 0}
      }

      assert {:error, :invoice_not_found} = Checkout.fulfill_session(session)
    end

    test "returns :missing_invoice_reference when no invoice id is present" do
      session = %{"id" => "cs_test_noref", "amount_total" => 1000, "currency" => "cad"}
      assert {:error, :missing_invoice_reference} = Checkout.fulfill_session(session)
    end
  end
end
