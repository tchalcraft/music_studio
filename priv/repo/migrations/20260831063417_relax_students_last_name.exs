defmodule MusicStudio.Repo.Migrations.RelaxStudentsLastName do
  use Ecto.Migration

  # Leads capture a single `name`, and some students go by one name — so last_name is
  # optional. first_name stays required.
  #
  # Use a raw ALTER … DROP NOT NULL (not Ecto's `modify`, which re-types the column and is
  # rejected while the analytics_lesson_facts view depends on last_name).
  def up do
    execute("ALTER TABLE students ALTER COLUMN last_name DROP NOT NULL")
  end

  def down do
    execute("ALTER TABLE students ALTER COLUMN last_name SET NOT NULL")
  end
end
