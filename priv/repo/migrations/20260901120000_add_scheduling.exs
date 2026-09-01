defmodule MusicStudio.Repo.Migrations.AddScheduling do
  use Ecto.Migration

  def up do
    alter table(:lessons) do
      add :google_event_id, :string
      add :booking_token, :string
    end

    create unique_index(:lessons, [:booking_token])

    # Hard double-booking guarantee: no two non-deleted scheduled lessons for the same
    # teacher may have overlapping [scheduled_start, scheduled_end) ranges. Columns are
    # `timestamp without time zone` (Ecto :utc_datetime stores UTC), so we use tsrange.
    execute "CREATE EXTENSION IF NOT EXISTS btree_gist"

    execute """
    ALTER TABLE lessons ADD CONSTRAINT lessons_no_overlap
      EXCLUDE USING gist (
        teacher_id WITH =,
        tsrange(scheduled_start, scheduled_end) WITH &&
      )
      WHERE (deleted_at IS NULL AND status = 'scheduled' AND scheduled_end IS NOT NULL)
    """

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

  def down do
    drop table(:scheduling_credentials)
    execute "ALTER TABLE lessons DROP CONSTRAINT IF EXISTS lessons_no_overlap"
    drop unique_index(:lessons, [:booking_token])

    alter table(:lessons) do
      remove :google_event_id
      remove :booking_token
    end
  end
end
