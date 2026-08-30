defmodule MusicStudio.Repo.Migrations.CreateLeads do
  use Ecto.Migration

  def change do
    create table(:leads) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :instrument, :string, null: false
      add :message, :text

      timestamps()
    end

    create index(:leads, [:inserted_at])
  end
end
