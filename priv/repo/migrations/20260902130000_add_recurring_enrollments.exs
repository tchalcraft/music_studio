defmodule MusicStudio.Repo.Migrations.AddRecurringEnrollments do
  use Ecto.Migration

  def change do
    alter table(:enrollments) do
      add :recurrence_interval_weeks, :integer
      add :recurrence_weekday, :integer
      add :recurrence_time, :time
      add :recurrence_timezone, :string
      add :booking_token, :string
      add :contact_email, :string
    end

    create unique_index(:enrollments, [:booking_token])
  end
end
