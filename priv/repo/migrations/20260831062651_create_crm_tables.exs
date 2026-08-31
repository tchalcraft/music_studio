defmodule MusicStudio.Repo.Migrations.CreateCrmTables do
  use Ecto.Migration

  def change do
    # Funnel fields on the pre-existing bigint `leads` table.
    alter table(:leads) do
      add :status, :string, null: false, default: "new"
      add :source, :string
      add :converted_student_id, references(:students, type: :uuid, on_delete: :nilify_all)
    end

    create index(:leads, [:status])
    create index(:leads, [:converted_student_id])

    create table(:campaigns, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :channel, :string, null: false, default: "other"
      add :started_on, :date
      add :ended_on, :date
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:touchpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :channel, :string, null: false, default: "email"
      add :direction, :string, null: false, default: "outbound"
      add :occurred_at, :utc_datetime_usec, null: false
      add :summary, :text
      add :metadata, :map, null: false, default: %{}
      add :lead_id, references(:leads, type: :bigint, on_delete: :nilify_all)
      add :student_id, references(:students, type: :uuid, on_delete: :nilify_all)
      add :campaign_id, references(:campaigns, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:touchpoints, [:lead_id])
    create index(:touchpoints, [:student_id])
    create index(:touchpoints, [:campaign_id])
    create index(:touchpoints, [:occurred_at])
  end
end
