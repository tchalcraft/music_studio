import Config

# Beacon runs in :testing mode during tests so it skips boot-time content population
# (default components/layouts/pages) — that work isn't needed by the test suite and
# would slow every run. Merges into the site config from config/config.exs.
config :beacon, music_studio: [mode: :testing]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :music_studio, MusicStudio.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "music_studio_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :music_studio, MusicStudioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "a10Tb1el53vnKzeEwVXH8dWKv22cFkBxlMcAWh/AXAcpd962JL5fLthev4lZZF2Z",
  server: false

# In test we don't send emails
config :music_studio, MusicStudio.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
