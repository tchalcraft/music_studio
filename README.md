# MusicStudio

Marketing website for **Tristan**, an independent music teacher — who he is, what he
teaches (voice, piano, guitar; in-person, all ages), his rates, and an inquiry form —
with a CMS so content can be edited without a developer.

## Stack

- **Elixir 1.18.4 / OTP 28**, pinned in `.tool-versions` and managed by
  [mise](https://mise.jdx.dev/) (`mise install` once, then `mix` uses the pinned versions).
- **Phoenix 1.7 + Phoenix LiveView 1.2** on the **Bandit** HTTP server.
  > Phoenix is held at `~> 1.7` because Beacon CMS 0.5.1 uses a Phoenix API removed in
  > 1.8. LiveView 1.2 supports 1.7, so it stays. See `../lessons.md` (2026-08-30).
- **PostgreSQL via Ecto** — **Neon** (hosted) in development, from `DATABASE_URL`.
- **Beacon CMS** (`beacon` + `beacon_live_admin`) — DB-backed pages/layouts/components;
  admin at [`/cms`](http://localhost:4000/cms). Mounted as a catch-all behind the
  hand-built home page (`HomeLive`), which currently owns `/`.
- **Tailwind CSS v4 + daisyUI**, plus a Radix-inspired "Modern Minimal" token layer
  (`ms-` classes in `assets/css/app.css`).
- **Swoosh** for inquiry-notification email; **gettext** for i18n.
- `MusicStudio.Leads` context captures inquiries (DB + email), independent of the CMS.

Key modules: app `MusicStudio`, web `MusicStudioWeb`; `MusicStudioWeb.HomeLive` (the
marketing page + inquiry form), `MusicStudio.Leads` / `Leads.Notifier`,
`MusicStudioWeb.BeaconRuntimeCSS` (Beacon CSS shim).

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

`config/dev.exs` uses **`DATABASE_URL`** when set (a Neon Postgres connection string —
a `postgresql://` URL ending in `?sslmode=require`), otherwise a local Postgres. Keep
that URL — with its password — in the workspace `.envrc` (git-ignored, loaded by
direnv); never commit it.

Then `mix ecto.migrate` runs against that database. Tests always use the local DB in
`config/test.exs`. In a `wt` worktree (which doesn't inherit the parent `.envrc`),
export `DATABASE_URL` yourself or add `.envrc` to `.worktreeinclude`.

## AI coding agents

Framework guidance is split into skills under `.claude/skills/` (mirrored to
`.agents/skills/`), each loading by trigger. See `AGENTS.md` for the project overview,
stack, and commands.

## Deploying

Production runs as an OTP release in a Docker container on **Render's free tier**, in
front of the same **Neon** Postgres, with **Cloudflare** providing DNS/CDN/SSL for
`tristanchalcraftmusic.com`. (Cloudflare can't run the BEAM, so it sits in front, not
instead of, the app host.)

- **`Dockerfile`** — multi-stage OTP release, pinned to the dev toolchain
  (Elixir 1.18.4 / OTP 28) because this Phoenix 1.7 + Beacon stack is version-sensitive.
  The container runs pending migrations then boots the server (`CMD` → `bin/migrate && bin/server`).
- **`render.yaml`** — Render Blueprint: one `plan: free` Docker web service. Connect Render
  directly to the `tchalcraft/music_studio` repo.
- **Env vars** (set in Render, never committed): `PHX_SERVER=true`, `DATABASE_URL` (Neon
  pooled URL), `SECRET_KEY_BASE` (`mix phx.gen.secret`), `PHX_HOST`, `POOL_SIZE=5`,
  `INQUIRY_TO_EMAIL` / `INQUIRY_FROM_EMAIL`. `config/runtime.exs` reads these and applies
  Neon's SSL + `prepare: :unnamed` (PgBouncer transaction mode) and a `check_origin`
  allow-list for LiveView behind the proxy.
- **Free-tier note:** the free web service sleeps after ~15 min idle (slow first request);
  the DB stays on Neon free (not Render Postgres). Media currently lives as Postgres BLOBs;
  offload to Cloudflare R2 later if Neon storage gets tight.

Full deployment/DNS/TLS runbook: `../docs/architecture.md` (Deployment section) and
`../checkpoint.md`. General Phoenix deploy docs: https://phoenix.hexdocs.pm/deployment.html.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
