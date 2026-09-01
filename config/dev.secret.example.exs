import Config

# Local development secrets.
#
# Copy this file to `config/dev.secret.exs` and fill in real values:
#
#     cp config/dev.secret.example.exs config/dev.secret.exs
#
# `config/dev.secret.exs` is git-ignored and imported by `config/dev.exs` only if
# it exists, so the app boots fine without it. `.worktreeinclude` lists it so
# worktree tooling copies your filled-in secrets into each new worktree.
#
# Keep real secrets OUT of version control. Production secrets are read from
# environment variables in `config/runtime.exs`, not from this file.
#
# Override where lesson-inquiry notifications are sent while developing locally
# (the default placeholder lives in config/config.exs; prod reads INQUIRY_TO_EMAIL):
#
#     config :music_studio, MusicStudio.Leads,
#       inquiry_to: "you@example.com",
#       inquiry_from: "no-reply@musicstudio.local"
#
# Stripe (Payments + Tax). Test-mode keys come from the STRIPE_* exports in the
# project-root .envrc (loaded by direnv); read them from the environment here so the
# real keys never live in a tracked file. Add this block to config/dev.secret.exs:
#
#     config :music_studio, :stripe,
#       secret_key: System.get_env("STRIPE_SECRET_KEY"),
#       publishable_key: System.get_env("STRIPE_PUBLISHABLE_KEY"),
#       webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")
#
# Other external service integrations (transactional email, analytics) will follow the
# same pattern as they land.
