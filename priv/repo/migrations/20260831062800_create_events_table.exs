defmodule MusicStudio.Repo.Migrations.CreateEventsTable do
  use Ecto.Migration

  # Append-only activity stream. No updated_at/deleted_at — events are immutable facts.
  def change do
    create table(:events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_type, :string
      add :actor_id, :string
      add :verb, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :string
      add :occurred_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:events, [:occurred_at])
    create index(:events, [:subject_type, :subject_id])
    create index(:events, [:verb])
  end
end
