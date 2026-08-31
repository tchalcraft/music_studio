defmodule MusicStudio.Repo.Migrations.CreateTeachingTables do
  use Ecto.Migration

  def change do
    create table(:guardians, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :email, :string
      add :phone, :string
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:students, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :email, :string
      add :phone, :string
      add :date_of_birth, :date
      add :status, :string, null: false, default: "prospective"
      add :notes, :text
      # Funnel origin: references the pre-existing bigint `leads` table.
      add :lead_id, references(:leads, type: :bigint, on_delete: :nilify_all)
      add :guardian_id, references(:guardians, type: :uuid, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:students, [:guardian_id])
    create index(:students, [:lead_id])
    create index(:students, [:status])

    create table(:enrollments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :string, null: false, default: "active"
      add :started_on, :date
      add :ended_on, :date
      add :deleted_at, :utc_datetime_usec
      add :student_id, references(:students, type: :uuid, on_delete: :restrict), null: false
      add :teacher_id, references(:teachers, type: :uuid, on_delete: :restrict), null: false
      add :instrument_id, references(:instruments, type: :uuid, on_delete: :restrict), null: false
      add :offering_id, references(:offerings, type: :uuid, on_delete: :nilify_all)
      add :location_id, references(:locations, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:enrollments, [:student_id])
    create index(:enrollments, [:teacher_id])
    create index(:enrollments, [:instrument_id])
    create index(:enrollments, [:status])

    create table(:lessons, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :scheduled_start, :utc_datetime, null: false
      add :scheduled_end, :utc_datetime
      add :duration_minutes, :integer
      add :status, :string, null: false, default: "scheduled"
      add :price_cents, :integer
      add :currency, :string, null: false, default: "CAD"
      add :notes, :text
      add :deleted_at, :utc_datetime_usec
      add :enrollment_id, references(:enrollments, type: :uuid, on_delete: :nilify_all)
      add :student_id, references(:students, type: :uuid, on_delete: :restrict), null: false
      add :teacher_id, references(:teachers, type: :uuid, on_delete: :restrict), null: false
      add :instrument_id, references(:instruments, type: :uuid, on_delete: :nilify_all)
      add :offering_id, references(:offerings, type: :uuid, on_delete: :nilify_all)
      add :location_id, references(:locations, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:lessons, [:scheduled_start])
    create index(:lessons, [:student_id])
    create index(:lessons, [:teacher_id])
    create index(:lessons, [:enrollment_id])
    create index(:lessons, [:status])
  end
end
