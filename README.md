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

## Online booking

Visitors book lessons at **`/book`**: pick an instrument + length (voice/piano/guitar;
30/45/60 min) as boxes, choose an open time, and it's booked instantly. Availability is
**app-defined working hours** — Monday–Friday 2:00–9:00 PM (`America/Vancouver`) minus
already-booked lessons, on a 30-min grid, with a buffer and a 24 h minimum notice; lessons
must end by 9 PM. Single lessons use a month calendar; **recurring** weekly / every-other-week
series run the school year (through Jun 30) with skip and month-long pause (the time stays
held), managed via `/book/manage/:token`. A booking creates a `Lesson` (as a prospective
`Student`), sends a branded Resend confirmation with a `.ics` attachment (+ a teacher
notification), and writes the lesson to Google Calendar. Lessons carry a price so they can be
invoiced monthly (Stripe) later — no payment at booking. A Postgres exclusion constraint makes
double-booking impossible.

**Google Calendar** uses a **service account** (no OAuth/consent flow): share the target
calendar with the service account's email, then set `GOOGLE_SERVICE_ACCOUNT_KEY` (the JSON
key) and `GOOGLE_AVAILABILITY_CALENDAR_ID`. Both are optional — without them the app still
runs (availability + booking work); it just won't write events to the calendar. Booking email
uses `RESEND_API_KEY`. Tunables live under `config :music_studio, MusicStudio.Scheduling`
(`studio_timezone`, `working_days`, `working_start`/`working_end`, `slot_grid_minutes`,
`buffer_minutes`, `min_notice_minutes`).

## AI coding agents

Framework guidance is split into skills under `.claude/skills/` (mirrored to
`.agents/skills/`), each loading by trigger. See `AGENTS.md` for the project overview,
stack, and commands.

## Testing & CI

- **`mix precommit`** is the local gate (compile-as-errors, skills sync, format, gettext,
  Credo, Sobelow, tests). Run it before pushing.
- **Property tests:** `stream_data` powers `test/music_studio/scheduling/availability_property_test.exs`,
  asserting the booking-availability invariants (grid alignment, block containment,
  min-notice, no-overlap-with-buffer) hold for generated inputs.
- **Browser property tests:** `e2e/` holds [Bombadil](https://antithesishq.github.io/bombadil/browser/1-introduction.html)
  specs that drive a real browser against the inquiry + booking flows. See `e2e/README.md`.
- **GitHub Actions** (`.github/workflows/`): `ci.yml` runs `mix precommit` on every push/PR
  to `main` — a **regression net, not a deploy gate** (deploys stay manual). `bombadil.yml`
  is a **manual** (`workflow_dispatch`) + weekly job that runs the browser specs against the
  live site — a post-deploy smoke test (GH runners can reach the domain; a corporate-network
  machine can't).

## Deploying

**Live at [tristanchalcraftmusic.com](https://tristanchalcraftmusic.com).** Production runs
as an OTP release in a Docker container on **Render's free tier**, in front of the **Neon**
`production` branch, with **Resend** for email. DNS is on **Porkbun** and points straight at
Render (Render issues the TLS cert) — no CDN layer in front for now.

- **`Dockerfile`** — multi-stage OTP release on **Debian bookworm**, pinned to the dev
  toolchain (Elixir 1.18.4 / OTP 28) because this Phoenix 1.7 + Beacon stack is
  version-sensitive. It compiles the app *before* assets (LiveView colocated hooks), ships
  the esbuild/tailwind binaries into the runner (Beacon compiles page JS/CSS at runtime),
  and runs migrations then boots the server (`CMD` → `bin/migrate && bin/server`).
- **`render.yaml`** — Render Blueprint: one `plan: free` Docker web service, built from this
  repo's `main`.
- **Env vars** (set in Render, never committed): `PHX_SERVER=true`, `DATABASE_URL` (Neon
  pooled URL), `SECRET_KEY_BASE` (`mix phx.gen.secret`), `PHX_HOST`, `POOL_SIZE=5`,
  `RESEND_API_KEY`, `INQUIRY_TO_EMAIL` / `INQUIRY_FROM_EMAIL`, and `STRIPE_SECRET_KEY`.
  `config/runtime.exs` reads these and applies Neon's SSL + `prepare: :unnamed` (PgBouncer
  transaction mode), a `check_origin` allow-list, and the Resend mailer.
- **Beacon boot:** `page_warming: :none` so pages compile lazily on first request rather
  than blocking boot (the free tier's CPU can't warm them within Beacon's timeout).
- **Free-tier notes:** the service sleeps after ~15 min idle (slow first request); the DB
  stays on Neon free (not Render Postgres). Media currently lives as Postgres BLOBs — offload
  to object storage (e.g. Cloudflare R2) later if Neon storage gets tight.

Full deployment/DNS/TLS runbook: `../docs/architecture.md` (Deployment section) and
`../checkpoint.md`. General Phoenix deploy docs: https://phoenix.hexdocs.pm/deployment.html.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
