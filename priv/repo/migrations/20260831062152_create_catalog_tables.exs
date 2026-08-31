defmodule MusicStudio.Repo.Migrations.CreateCatalogTables do
  use Ecto.Migration

  # Reference/dimension tables. UUIDv7 primary keys (`:uuid` columns; the app generates
  # the values via MusicStudio.Schema), microsecond timestamps, and soft-delete columns.
  def change do
    create table(:teachers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :email, :string
      add :bio, :text
      add :active, :boolean, null: false, default: true
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:locations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :kind, :string, null: false, default: "in_person"
      add :address_line, :string
      add :city, :string
      add :region, :string
      add :postal_code, :string
      add :active, :boolean, null: false, default: true
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:instruments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :active, :boolean, null: false, default: true
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:instruments, [:slug])

    create table(:offerings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :duration_minutes, :integer, null: false
      add :price_cents, :integer, null: false
      add :currency, :string, null: false, default: "CAD"
      add :active, :boolean, null: false, default: true
      add :deleted_at, :utc_datetime_usec
      add :instrument_id, references(:instruments, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:offerings, [:instrument_id])
  end
end
