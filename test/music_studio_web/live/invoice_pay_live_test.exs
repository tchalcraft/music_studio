defmodule MusicStudioWeb.InvoicePayLiveTest do
  use MusicStudioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MusicStudio.Billing

  defp create_invoice(status) do
    {:ok, invoice} =
      Billing.create_invoice(%{
        status: status,
        currency: "CAD",
        subtotal_cents: 6000,
        total_cents: 6000,
        issued_on: Date.utc_today()
      })

    invoice
  end

  test "renders the invoice amount and a pay button for an open invoice", %{conn: conn} do
    invoice = create_invoice(:open)

    {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}/pay")

    assert has_element?(view, "#pay-now")
    assert has_element?(view, "#invoice-subtotal", "$60.00 CAD")
  end

  test "shows a paid state for a paid invoice", %{conn: conn} do
    invoice = create_invoice(:paid)

    {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}/pay")

    assert has_element?(view, "#invoice-paid")
    refute has_element?(view, "#pay-now")
  end

  test "shows a not-found state for an unknown invoice", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/invoices/#{Ecto.UUID.generate()}/pay")

    assert has_element?(view, "#invoice-not-found")
  end

  test "the success page thanks the payer", %{conn: conn} do
    invoice = create_invoice(:open)

    {:ok, view, _html} = live(conn, ~p"/invoices/#{invoice.id}/pay/success")

    assert has_element?(view, "#pay-success")
  end
end
