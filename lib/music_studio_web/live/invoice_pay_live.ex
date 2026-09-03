defmodule MusicStudioWeb.InvoicePayLive do
  @moduledoc """
  Public "pay this invoice" page. Reached at `/invoices/:id/pay` (the id is an unguessable
  UUIDv7 — there is no auth yet). "Pay now" opens a Stripe Checkout Session (with Stripe
  Tax) and redirects to Stripe's hosted page; `/success` and `/cancel` are the return URLs.

  Fulfillment happens in the webhook (`MusicStudioWeb.StripeWebhookController`), not here —
  the success page only thanks the payer, since the webhook may still be in flight.
  """
  use MusicStudioWeb, :live_view

  alias MusicStudio.Billing
  alias MusicStudio.Billing.Stripe

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:invoice, fetch_invoice(id))
     |> assign(:error, nil)
     |> assign(:page_title, "Pay invoice")}
  end

  @impl true
  def handle_event("pay", _params, socket) do
    invoice = socket.assigns.invoice

    opts = [
      success_url: url(~p"/invoices/#{invoice.id}/pay/success"),
      cancel_url: url(~p"/invoices/#{invoice.id}/pay/cancel")
    ]

    case Stripe.create_checkout_session(invoice, opts) do
      {:ok, %{url: checkout_url}} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, _reason} ->
        {:noreply,
         assign(socket, :error, "We couldn't start checkout just now. Please try again.")}
    end
  end

  defp fetch_invoice(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Billing.get_invoice(uuid)
      :error -> nil
    end
  end

  defp money(cents, currency) when is_integer(cents) do
    dollars = div(cents, 100)
    cents_part = abs(cents) |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "$#{dollars}.#{cents_part} #{currency}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="ms-root">
      <main class="ms-section">
        <div class="ms-container" style="max-width:32rem">
          <%= cond do %>
            <% is_nil(@invoice) -> %>
              <div class="ms-card" id="invoice-not-found">
                <h1 class="ms-card__title">Invoice not found</h1>
                <p class="ms-note">
                  We couldn't find that invoice. Please check the link, or contact the studio.
                </p>
              </div>
            <% @live_action == :success -> %>
              <div class="ms-card" id="pay-success">
                <h1 class="ms-card__title">Thank you — payment received</h1>
                <p class="ms-note">
                  Your payment is being confirmed and a receipt will follow by email. You can
                  close this page.
                </p>
              </div>
            <% @live_action == :cancel -> %>
              <div class="ms-card" id="pay-cancel">
                <h1 class="ms-card__title">Payment canceled</h1>
                <p class="ms-note">No charge was made.</p>
                <p style="margin-top:1.5rem">
                  <.link navigate={~p"/invoices/#{@invoice.id}/pay"} class="ms-btn ms-btn--primary">
                    Back to invoice
                  </.link>
                </p>
              </div>
            <% @invoice.status == :paid -> %>
              <div class="ms-card" id="invoice-paid">
                <h1 class="ms-card__title">This invoice is paid</h1>
                <p class="ms-note">Thank you! Nothing more is due.</p>
              </div>
            <% true -> %>
              <div class="ms-card" id="invoice-pay">
                <p class="ms-eyebrow">Music Studio</p>
                <h1 class="ms-card__title">Pay your invoice</h1>

                <dl class="ms-list" style="margin-top:1.5rem">
                  <div style="display:flex;justify-content:space-between">
                    <dt>Amount due</dt>
                    <dd id="invoice-subtotal">{money(@invoice.subtotal_cents, @invoice.currency)}</dd>
                  </div>
                </dl>

                <%= if @error do %>
                  <p class="ms-error" id="pay-error" style="margin-top:1rem">{@error}</p>
                <% end %>

                <button
                  type="button"
                  id="pay-now"
                  phx-click="pay"
                  class="ms-btn ms-btn--primary ms-btn--block"
                  style="margin-top:1.5rem"
                >
                  Pay now
                </button>
              </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end
end
