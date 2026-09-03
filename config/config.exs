# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :music_studio,
  ecto_repos: [MusicStudio.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :music_studio, MusicStudioWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MusicStudioWeb.ErrorHTML, json: MusicStudioWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MusicStudio.PubSub,
  live_view: [signing_salt: "puLjeM5S"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :music_studio, MusicStudio.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  music_studio: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  music_studio: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Beacon CMS site. Served at "/" (as a catch-all behind the hand-built home page for
# now) with the admin at "/cms". Backed by MusicStudio.Repo — which in dev points at
# Neon via DATABASE_URL — so Beacon's content lives in the same database.
config :beacon,
  music_studio: [
    site: :music_studio,
    repo: MusicStudio.Repo,
    endpoint: MusicStudioWeb.Endpoint,
    router: MusicStudioWeb.Router,
    # Beacon 0.5.1's Tailwind compiler assumes Tailwind v3; this app is on v4. Use a
    # lightweight CSS compiler so Beacon boots/serves; full page styling is a follow-up.
    css_compiler: MusicStudioWeb.BeaconRuntimeCSS,
    # Don't warm (compile) CMS pages at boot. On the free-tier host (0.5 vCPU) eager
    # warming blows Beacon's 15s per-page load_page_module timeout and crashes boot;
    # :none makes pages compile lazily on first request instead (negligible in dev).
    page_warming: :none
  ]

# Where new-inquiry notifications are sent. These are non-secret placeholders; the
# real destination is set per environment — from an env var in prod (runtime.exs) and
# overridable locally in config/dev.secret.exs.
config :music_studio, MusicStudio.Leads,
  inquiry_to: "owner@example.com",
  inquiry_from: "no-reply@musicstudio.local"

# Stripe (Payments + Tax). Non-secret placeholders; the real keys are set per
# environment — from STRIPE_* env vars in prod (runtime.exs) and locally in
# config/dev.secret.exs. `api_base_url` is here so tests can point the client at a stub.
config :music_studio, :stripe,
  secret_key: nil,
  publishable_key: nil,
  webhook_secret: nil,
  api_base_url: "https://api.stripe.com"

# Use the tzdata time zone database for DateTime math (Pacific slots, DST).
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Scheduling / online booking defaults. Secrets (Google, Resend) are injected in
# config/runtime.exs (prod) or config/dev.secret.exs (local); never commit them.
config :music_studio, MusicStudio.Scheduling,
  studio_timezone: "America/Vancouver",
  slot_grid_minutes: 30,
  buffer_minutes: 15,
  min_notice_minutes: 24 * 60,
  # Bookable window (studio-local): Mon–Fri, 2:00 PM–9:00 PM. Lessons must end by
  # working_end, so nothing runs past 9 PM. Availability = this window minus booked lessons.
  working_days: [1, 2, 3, 4, 5],
  working_start: ~T[14:00:00],
  working_end: ~T[21:00:00],
  google_token_url: "https://oauth2.googleapis.com/token",
  service_account_key: nil,
  availability_calendar_id: nil,
  target_calendar_id: nil,
  notify_from: "no-reply@musicstudio.local",
  notify_to: "owner@example.com",
  website_url: nil,
  social: [instagram: nil, facebook: nil, youtube: nil]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
