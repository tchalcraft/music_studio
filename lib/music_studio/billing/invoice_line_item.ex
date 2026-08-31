defmodule MusicStudio.Billing.InvoiceLineItem do
  @moduledoc "A line on an invoice, optionally tied to a specific lesson and/or offering."
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Billing.Invoice
  alias MusicStudio.Catalog.Offering
  alias MusicStudio.Teaching.Lesson

  schema "invoice_line_items" do
    field :description, :string
    field :quantity, :integer, default: 1
    field :unit_price_cents, :integer
    field :amount_cents, :integer

    belongs_to :invoice, Invoice
    belongs_to :lesson, Lesson
    belongs_to :offering, Offering

    timestamps()
  end

  @doc false
  def changeset(line_item, attrs) do
    line_item
    |> cast(attrs, [
      :description,
      :quantity,
      :unit_price_cents,
      :amount_cents,
      :invoice_id,
      :lesson_id,
      :offering_id
    ])
    |> validate_required([:description, :quantity, :unit_price_cents, :amount_cents, :invoice_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:invoice)
    |> assoc_constraint(:lesson)
    |> assoc_constraint(:offering)
  end
end
