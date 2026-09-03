defmodule MusicStudio.Repo.Migrations.DropSchedulingCredentials do
  use Ecto.Migration

  # The OAuth connect flow is gone; Google auth now uses a service-account key from config,
  # so the stored-credential table is no longer needed.
  def up do
    drop table(:scheduling_credentials)
  end

  def down do
    create table(:scheduling_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false, default: "google"
      add :refresh_token, :text
      add :access_token, :text
      add :access_token_expires_at, :utc_datetime_usec
      add :availability_calendar_id, :string
      add :target_calendar_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:scheduling_credentials, [:provider])
  end
end
