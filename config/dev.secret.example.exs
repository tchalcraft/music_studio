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
# Other external service integrations (billing, transactional email, analytics) are
# planned for later phases. Add their keys here when those phases land, for example:
#
#     config :music_studio, :some_service, api_key: "dev-only-key"
