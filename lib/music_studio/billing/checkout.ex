defmodule MusicStudio.Billing.Checkout do
  @moduledoc """
  Fulfillment for Stripe Checkout: turns a completed `checkout.session.completed` session
  into a recorded `Payment` and a paid `Invoice`.

  Driven by the webhook (`MusicStudioWeb.StripeWebhookController`), never by the browser
  redirect — the redirect can be skipped or forged. Fulfillment is idempotent on the
  Stripe Checkout Session id, so Stripe's retries are safe.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias MusicStudio.Analytics
  alias MusicStudio.Billing.Invoice
  alias MusicStudio.Billing.Payment
  alias MusicStudio.Repo

  @doc """
  Records payment for a completed Checkout Session.

  Expects the Stripe session object (the `data.object` of a `checkout.session.completed`
  event). In one transaction: inserts a `:stripe` `Payment`, sets the invoice's
  `tax_cents`/`total_cents` and marks it `:paid`, and records an analytics event.

  Returns `{:ok, payment}`, `{:ok, :already_fulfilled}` if this session was already
  processed, or `{:error, reason}` (`:invoice_not_found`, `:missing_invoice_reference`, or
  a changeset).
  """
  @spec fulfill_session(map()) ::
          {:ok, Payment.t()} | {:ok, :already_fulfilled} | {:error, term()}
  def fulfill_session(%{"id" => session_id} = session) when is_binary(session_id) do
    case Repo.get_by(Payment, stripe_checkout_session_id: session_id) do
      %Payment{} -> {:ok, :already_fulfilled}
      nil -> do_fulfill(session_id, session)
    end
  end

  def fulfill_session(_session), do: {:error, :missing_session_id}

  defp do_fulfill(session_id, session) do
    case invoice_reference(session) do
      nil ->
        {:error, :missing_invoice_reference}

      invoice_id ->
        Multi.new()
        |> Multi.run(:invoice, fn repo, _ -> fetch_invoice(repo, invoice_id) end)
        |> Multi.insert(:payment, fn %{invoice: invoice} ->
          payment_changeset(invoice, session_id, session)
        end)
        |> Multi.update(:paid_invoice, fn %{invoice: invoice} ->
          invoice_changeset(invoice, session)
        end)
        |> Multi.run(:event, fn _repo, %{invoice: invoice, payment: payment} ->
          record_event(invoice, payment, session_id, session)
        end)
        |> Repo.transaction()
        |> handle_result(session_id)
    end
  end

  defp handle_result({:ok, %{payment: payment}}, _session_id), do: {:ok, payment}

  defp handle_result({:error, :invoice, :not_found, _changes}, _sid),
    do: {:error, :invoice_not_found}

  defp handle_result({:error, :payment, %Ecto.Changeset{} = changeset, _changes}, _sid) do
    # Lost a race with a concurrent retry: the unique index on the session id fired.
    if Keyword.has_key?(changeset.errors, :stripe_checkout_session_id) do
      {:ok, :already_fulfilled}
    else
      {:error, changeset}
    end
  end

  defp handle_result({:error, _step, reason, _changes}, _sid), do: {:error, reason}

  defp fetch_invoice(repo, invoice_id) do
    case repo.get(Invoice, invoice_id) do
      %Invoice{} = invoice -> {:ok, invoice}
      nil -> {:error, :not_found}
    end
  end

  defp payment_changeset(%Invoice{} = invoice, session_id, session) do
    Payment.changeset(%Payment{}, %{
      invoice_id: invoice.id,
      guardian_id: invoice.guardian_id,
      student_id: invoice.student_id,
      amount_cents: session["amount_total"],
      currency: currency(session, invoice),
      method: :stripe,
      paid_at: DateTime.utc_now(),
      reference: session["payment_intent"],
      stripe_checkout_session_id: session_id,
      stripe_payment_intent_id: session["payment_intent"]
    })
  end

  defp invoice_changeset(%Invoice{} = invoice, session) do
    Invoice.changeset(invoice, %{
      status: :paid,
      tax_cents: amount_tax(session),
      total_cents: session["amount_total"]
    })
  end

  defp record_event(%Invoice{} = invoice, %Payment{} = payment, session_id, session) do
    Analytics.record_event(%{
      actor_type: "guardian",
      actor_id: invoice.guardian_id,
      verb: "invoice_paid",
      subject_type: "invoice",
      subject_id: invoice.id,
      metadata: %{
        payment_id: payment.id,
        amount_cents: payment.amount_cents,
        tax_cents: amount_tax(session),
        method: "stripe",
        stripe_checkout_session_id: session_id
      }
    })
  end

  defp invoice_reference(session) do
    session["client_reference_id"] || get_in(session, ["metadata", "invoice_id"])
  end

  defp amount_tax(session), do: get_in(session, ["total_details", "amount_tax"]) || 0

  defp currency(session, %Invoice{currency: fallback}) do
    case session["currency"] do
      currency when is_binary(currency) -> String.upcase(currency)
      _ -> fallback || "CAD"
    end
  end
end
