defmodule MusicStudio.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :music_studio

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Seeds reference/catalog data (teacher, location, instruments, offerings) by running the
  idempotent `priv/repo/seeds.exs`. Run on every deploy after `migrate` — without this the
  production catalog is empty and the booking page has no instruments/lengths to pick, so
  no one can book. Safe to re-run (each insert is upsert-guarded on a natural key).
  """
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seeds = Application.app_dir(@app, "priv/repo/seeds.exs")
          if File.exists?(seeds), do: Code.eval_file(seeds)
        end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
