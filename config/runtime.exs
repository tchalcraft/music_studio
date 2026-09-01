import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/music_studio start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :music_studio, MusicStudioWeb.Endpoint, server: true
end

config :music_studio, MusicStudioWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :music_studio, MusicStudioWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/music_studio_web/router\.ex$",
        ~r"lib/music_studio_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Where new-inquiry notifications go in production. Set INQUIRY_TO_EMAIL (and
  # optionally INQUIRY_FROM_EMAIL) in the environment; never commit real addresses.
  if to_addr = System.get_env("INQUIRY_TO_EMAIL") do
    config :music_studio, MusicStudio.Leads,
      inquiry_to: to_addr,
      inquiry_from: System.get_env("INQUIRY_FROM_EMAIL") || "no-reply@musicstudio.local"
  end

  # Stripe (Payments + Tax). The secret key is required; the publishable key and webhook
  # signing secret are read from the environment too (the webhook secret is only needed
  # once the checkout webhook endpoint exists). Set these as deploy env vars / GitHub
  # Actions secrets — never commit real keys.
  config :music_studio, :stripe,
    secret_key:
      System.get_env("STRIPE_SECRET_KEY") ||
        raise("""
        environment variable STRIPE_SECRET_KEY is missing.
        Set it to your Stripe secret key, e.g.: sk_live_...
        """),
    publishable_key: System.get_env("STRIPE_PUBLISHABLE_KEY"),
    webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

  config :music_studio, MusicStudio.Repo,
    # Drop any libpq query params (e.g. ?sslmode=require&channel_binding=require) that
    # Postgrex doesn't accept; SSL is configured explicitly below. Mirrors config/dev.exs.
    url: database_url |> String.split("?") |> hd(),
    ssl: [verify: :verify_none],
    # Neon's pooled endpoint runs PgBouncer in transaction mode, which is incompatible
    # with named prepared statements — use unnamed ones to avoid "prepared statement
    # already exists" errors.
    prepare: :unnamed,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :music_studio, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :music_studio, MusicStudioWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    # LiveView runs behind a reverse proxy (Render, and Cloudflare in front), so the
    # websocket Origin must be checked against the public host(s) rather than the
    # internal one. Derived from PHX_HOST — apex + www, https only.
    check_origin: [
      "https://#{host}",
      "https://www.#{host}"
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :music_studio, MusicStudioWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :music_studio, MusicStudioWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Mailer: send inquiry notifications via Resend in production. Only override the
  # compile-time Local adapter (config/config.exs) when RESEND_API_KEY is set, so a deploy
  # without the key degrades gracefully — leads still persist, no email goes out — instead
  # of crashing boot. The API client (Swoosh.ApiClient.Req) is set in config/prod.exs.
  # The From address (INQUIRY_FROM_EMAIL) must be on a Resend-verified domain.
  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :music_studio, MusicStudio.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key
  end
end
