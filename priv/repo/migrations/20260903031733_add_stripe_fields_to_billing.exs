defmodule MusicStudio.Repo.Migrations.AddStripeFieldsToBilling do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :stripe_checkout_session_id, :string
      add :stripe_payment_intent_id, :string
    end

    # One payment per Checkout Session — the fulfillment idempotency key. Partial so
    # non-Stripe payments (null session id) aren't forced unique.
    create unique_index(:payments, [:stripe_checkout_session_id],
             where: "stripe_checkout_session_id IS NOT NULL"
           )

    alter table(:invoices) do
      add :tax_cents, :integer, null: false, default: 0
    end
  end
end
