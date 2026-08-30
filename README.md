# MusicStudio

Marketing website for an independent music teacher / studio, built with Phoenix.

The toolchain (Elixir 1.18.4 / Erlang OTP 28) is pinned in `.tool-versions` and
managed by [mise](https://mise.jdx.dev/) — run `mise install` once, then `mix`
commands use the pinned versions.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies (fetches deps, creates + migrates
  + seeds the database, installs and builds assets)
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
  (set `PORT=4001` to run alongside another worktree)

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Run `mix precommit` before pushing — it compiles with warnings as errors, checks
formatting and skills sync, runs Credo, Sobelow, and the test suite.

## Local secrets

Local development secrets live in `config/dev.secret.exs`, which is **git-ignored**.
Copy the tracked template and fill in values:

```sh
cp config/dev.secret.example.exs config/dev.secret.exs
```

`config/dev.exs` imports it only if present, so the app boots without it. Production
secrets are read from environment variables in `config/runtime.exs`, never committed.
`.worktreeinclude` lists `config/dev.secret.exs` so worktree tooling copies your
filled-in secrets into each new worktree (a fresh worktree has only tracked files).

### Development database

`config/dev.exs` uses **`DATABASE_URL`** when set (a Neon Postgres URL), otherwise a
local Postgres. Keep the URL — with its password — in the workspace `.envrc`
(git-ignored, loaded by direnv); never commit it. Example:

```sh
export DATABASE_URL="<your-neon-connection-string>"
```

Then `mix ecto.migrate` runs against that database. Tests always use the local DB in
`config/test.exs`. In a `wt` worktree (which doesn't inherit the parent `.envrc`),
export `DATABASE_URL` yourself or add `.envrc` to `.worktreeinclude`.

## AI coding agents

Framework guidance is split into skills under `.claude/skills/` (mirrored to
`.agents/skills/`), each loading by trigger. See `AGENTS.md` for the project overview,
stack, and commands.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
