defmodule MusicStudio.Repo.Migrations.CreateBillingTables do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :string, null: false, default: "draft"
      add :issued_on, :date
      add :due_on, :date
      add :subtotal_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "CAD"
      add :deleted_at, :utc_datetime_usec
      add :guardian_id, references(:guardians, type: :uuid, on_delete: :nilify_all)
      add :student_id, references(:students, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:invoices, [:guardian_id])
    create index(:invoices, [:student_id])
    create index(:invoices, [:status])

    create table(:invoice_line_items, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :description, :string, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_price_cents, :integer, null: false
      add :amount_cents, :integer, null: false
      add :invoice_id, references(:invoices, type: :uuid, on_delete: :delete_all), null: false
      add :lesson_id, references(:lessons, type: :uuid, on_delete: :nilify_all)
      add :offering_id, references(:offerings, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:invoice_line_items, [:invoice_id])
    create index(:invoice_line_items, [:lesson_id])

    create table(:payments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "CAD"
      add :method, :string, null: false, default: "e_transfer"
      add :paid_at, :utc_datetime_usec
      add :reference, :string
      add :deleted_at, :utc_datetime_usec
      add :invoice_id, references(:invoices, type: :uuid, on_delete: :nilify_all)
      add :guardian_id, references(:guardians, type: :uuid, on_delete: :nilify_all)
      add :student_id, references(:students, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:payments, [:invoice_id])
    create index(:payments, [:paid_at])
    create index(:payments, [:method])
  end
end
