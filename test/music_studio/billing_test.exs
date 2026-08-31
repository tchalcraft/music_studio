defmodule MusicStudio.BillingTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Billing
  alias MusicStudio.Billing.Invoice
  alias MusicStudio.Billing.Payment
  alias MusicStudio.Teaching

  test "invoice → line item → payment round-trip" do
    {:ok, guardian} = Teaching.create_guardian(%{first_name: "Pat", last_name: "Payer"})

    assert {:ok, %Invoice{} = invoice} =
             Billing.create_invoice(%{
               guardian_id: guardian.id,
               status: :open,
               currency: "CAD",
               subtotal_cents: 6000,
               total_cents: 6000,
               issued_on: Date.utc_today()
             })

    assert {:ok, line_item} =
             Billing.create_line_item(%{
               invoice_id: invoice.id,
               description: "60-minute lesson",
               quantity: 1,
               unit_price_cents: 6000,
               amount_cents: 6000
             })

    assert line_item.amount_cents == 6000

    assert {:ok, %Payment{} = payment} =
             Billing.create_payment(%{
               invoice_id: invoice.id,
               guardian_id: guardian.id,
               amount_cents: 6000,
               currency: "CAD",
               method: :e_transfer,
               paid_at: DateTime.utc_now()
             })

    assert payment.method == :e_transfer
    assert [%Payment{}] = Billing.list_payments()
  end

  test "payment requires a positive amount" do
    assert {:error, changeset} =
             Billing.create_payment(%{amount_cents: 0, currency: "CAD", method: :cash})

    assert errors_on(changeset).amount_cents != []
  end

  test "line item requires an invoice" do
    assert {:error, changeset} =
             Billing.create_line_item(%{
               description: "x",
               quantity: 1,
               unit_price_cents: 1,
               amount_cents: 1
             })

    assert "can't be blank" in errors_on(changeset).invoice_id
  end
end
