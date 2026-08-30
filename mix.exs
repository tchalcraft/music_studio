defmodule MusicStudio.MixProject do
  use Mix.Project

  def project do
    [
      app: :music_studio,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MusicStudio.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Pinned to 1.7.x so Beacon CMS (0.5.1) works: it calls a private Phoenix API
      # (`Phoenix.Endpoint.Supervisor.config/2`) that was removed in Phoenix 1.8.
      # LiveView 1.2 supports Phoenix ~> 1.7, so it stays put.
      {:phoenix, "~> 1.7.0"},
      {:beacon, "~> 0.5"},
      {:beacon_live_admin, "~> 0.4"},
      # Beacon pulls ex_aws transitively (media library); pin a version that compiles
      # on Elixir 1.18 (older 2.4.x hits an @partitions/Reference escape error).
      {:ex_aws, "~> 2.5", override: true},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # Beacon requires gettext ~> 0.26 (which already has the Gettext.Backend API
      # this app uses); can't be ~> 1.0 while Beacon is a dep.
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind music_studio", "esbuild music_studio"],
      "assets.deploy": [
        "tailwind music_studio --minify",
        "esbuild music_studio --minify",
        "phx.digest"
      ],
      precommit: [
        # --force guarantees a clean warnings-as-errors compile: without it, beams
        # left loaded/stale by later precommit tasks make a subsequent run's compile
        # emit spurious "redefining module" warnings this gate treats as errors.
        # Forcing a from-scratch app compile keeps the gate deterministic.
        "compile --warnings-as-errors --force",
        "skills.check",
        "deps.unlock --unused",
        "format",
        "gettext.extract --check-up-to-date",
        "credo --strict",
        "sobelow",
        "test"
      ]
    ]
  end
end
