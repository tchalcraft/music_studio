defmodule MusicStudio.Billing do
  @moduledoc """
  Billing domain: invoices, their line items, and payments. Revenue analytics source.
  List functions exclude soft-deleted rows.
  """
  import Ecto.Query, warn: false

  alias MusicStudio.Billing.Invoice
  alias MusicStudio.Billing.InvoiceLineItem
  alias MusicStudio.Billing.Payment
  alias MusicStudio.Repo

  ## Invoices

  def list_invoices, do: Repo.all(from i in active_scope(Invoice), order_by: [desc: i.issued_on])

  def get_invoice!(id), do: Repo.get!(Invoice, id)

  def change_invoice(%Invoice{} = i \\ %Invoice{}, attrs \\ %{}), do: Invoice.changeset(i, attrs)

  def create_invoice(attrs \\ %{}), do: %Invoice{} |> Invoice.changeset(attrs) |> Repo.insert()

  def update_invoice(%Invoice{} = i, attrs), do: i |> Invoice.changeset(attrs) |> Repo.update()

  ## Line items

  def create_line_item(attrs \\ %{}),
    do: %InvoiceLineItem{} |> InvoiceLineItem.changeset(attrs) |> Repo.insert()

  def change_line_item(%InvoiceLineItem{} = li \\ %InvoiceLineItem{}, attrs \\ %{}),
    do: InvoiceLineItem.changeset(li, attrs)

  ## Payments

  def list_payments, do: Repo.all(from p in active_scope(Payment), order_by: [desc: p.paid_at])

  def get_payment!(id), do: Repo.get!(Payment, id)

  def change_payment(%Payment{} = p \\ %Payment{}, attrs \\ %{}), do: Payment.changeset(p, attrs)

  def create_payment(attrs \\ %{}), do: %Payment{} |> Payment.changeset(attrs) |> Repo.insert()

  def update_payment(%Payment{} = p, attrs), do: p |> Payment.changeset(attrs) |> Repo.update()

  defp active_scope(queryable), do: from(r in queryable, where: is_nil(r.deleted_at))
end
