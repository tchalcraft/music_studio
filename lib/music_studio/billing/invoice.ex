defmodule MusicStudio.Billing.Invoice do
  @moduledoc "A bill issued to a guardian (or directly to a student), with line items and payments."
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Billing.InvoiceLineItem
  alias MusicStudio.Billing.Payment
  alias MusicStudio.Teaching.Guardian
  alias MusicStudio.Teaching.Student

  @statuses [:draft, :open, :paid, :void, :overdue]

  schema "invoices" do
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :issued_on, :date
    field :due_on, :date
    field :subtotal_cents, :integer, default: 0
    field :total_cents, :integer, default: 0
    field :currency, :string, default: "CAD"
    field :deleted_at, :utc_datetime_usec

    belongs_to :guardian, Guardian
    belongs_to :student, Student
    has_many :line_items, InvoiceLineItem
    has_many :payments, Payment

    timestamps()
  end

  @doc "Allowed invoice statuses."
  def statuses, do: @statuses

  @doc false
  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :status,
      :issued_on,
      :due_on,
      :subtotal_cents,
      :total_cents,
      :currency,
      :deleted_at,
      :guardian_id,
      :student_id
    ])
    |> validate_required([:status, :currency])
    |> validate_number(:subtotal_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:guardian)
    |> assoc_constraint(:student)
  end
end
