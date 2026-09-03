defmodule MusicStudio.Billing.Payment do
  @moduledoc "A payment against an invoice. Methods reflect the studio: cash or e-transfer (card/other for the future)."
  use MusicStudio.Schema
  import Ecto.Changeset

  alias MusicStudio.Billing.Invoice
  alias MusicStudio.Teaching.Guardian
  alias MusicStudio.Teaching.Student

  @methods [:cash, :e_transfer, :card, :stripe, :other]

  schema "payments" do
    field :amount_cents, :integer
    field :currency, :string, default: "CAD"
    field :method, Ecto.Enum, values: @methods, default: :e_transfer
    field :paid_at, :utc_datetime_usec
    field :reference, :string
    field :stripe_checkout_session_id, :string
    field :stripe_payment_intent_id, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :invoice, Invoice
    belongs_to :guardian, Guardian
    belongs_to :student, Student

    timestamps()
  end

  @doc "Allowed payment methods."
  def methods, do: @methods

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :amount_cents,
      :currency,
      :method,
      :paid_at,
      :reference,
      :stripe_checkout_session_id,
      :stripe_payment_intent_id,
      :deleted_at,
      :invoice_id,
      :guardian_id,
      :student_id
    ])
    |> validate_required([:amount_cents, :currency, :method])
    |> validate_number(:amount_cents, greater_than: 0)
    |> assoc_constraint(:invoice)
    |> assoc_constraint(:guardian)
    |> assoc_constraint(:student)
    |> unique_constraint(:stripe_checkout_session_id)
  end
end
