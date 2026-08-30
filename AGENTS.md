# MusicStudio

Marketing website for an independent music teacher / studio, built with Phoenix.

Task-specific framework guidance lives in `.claude/skills/` (mirrored to
`.agents/skills/`). Each skill loads automatically when its triggers match the work
you're doing — read the relevant one before writing code in that area. This file
holds only what is always true.

## Product scope

- **In scope now:** public marketing pages (home, about, lessons, contact) and a
  **leads** contact/inquiry form that captures prospective students.
- **Planned, later phases (out of scope for now):** billing/payments, lesson
  calendar & scheduling, marketing automation / newsletter, and web analytics.
  Do not scaffold these until their phase — see the project repo's `docs/phases.md`.

## Stack

- **Language/runtime:** Elixir 1.18.4 on Erlang/OTP 28, pinned in `.tool-versions`
  and managed by **mise** (mise is authoritative here; run `mix` under mise).
- **Framework:** **Phoenix `~> 1.7`** (LiveView 1.2, Bandit). **Do not upgrade Phoenix
  to 1.8** — Beacon CMS 0.5.1 calls a Phoenix API removed in 1.8. See `../lessons.md`.
- **CMS:** **Beacon** (`beacon` + `beacon_live_admin`), site `:music_studio`. Admin at
  `/cms`; `beacon_site "/"` is a catch-all mounted **after** `HomeLive`. Runtime CSS uses
  a custom `MusicStudioWeb.BeaconRuntimeCSS` (Beacon's Tailwind-v3 compiler is bypassed;
  the app is on Tailwind v4). Beacon runs `mode: :testing` under test env.
- **Database:** PostgreSQL via Ecto (`ecto_sql`, `postgrex`). Dev uses **Neon** from
  `DATABASE_URL` (`.envrc`); falls back to local Postgres. Beacon shares `MusicStudio.Repo`.
- **CSS:** Tailwind CSS v4 (no `tailwind.config.js`) + daisyUI; a Radix "Modern Minimal"
  token layer + `ms-` classes lives in `assets/css/app.css`. Assets bundled by esbuild + `tailwind`.
- **HTTP client:** `Req` — **avoid** `:httpoison`, `:tesla`, and `:httpc`.
- **Email:** Swoosh. **i18n:** gettext (`~> 0.26`, required by Beacon).
- **Modules:** app module `MusicStudio`, web module `MusicStudioWeb`.
- **Domain:** `MusicStudio.Leads` (inquiries) + `Leads.Notifier`; `MusicStudioWeb.HomeLive`
  (marketing page + inquiry form).

## Commands

- `mix setup` — fetch deps, create+migrate+seed the DB, install/build assets.
- `mix phx.server` — start the app (http://localhost:4000). Honors `PORT`.
- `mix test` — run the test suite.
- `mix precommit` — the gate: `compile --warnings-as-errors`, `skills.check`,
  `deps.unlock --unused`, `format`, `gettext.extract --check-up-to-date`,
  `credo --strict`, `sobelow`, `test`. Must exit 0 before work is done.

## Verification

- Write tests for new behavior (see the `phoenix-liveview` skill for LiveView tests).
- Run `mix precommit` and fix anything it reports; it must exit 0.
- Exercise UI changes in a browser, not just in tests.

## Local development

- Bootstrap a fresh checkout with `mix setup`.
- **Parallel worktrees:** override the port, e.g. `PORT=4001 mix phx.server`, so
  multiple worktrees can run at once.
- **Local secrets** live in `config/dev.secret.exs` (git-ignored). Copy the committed
  template `config/dev.secret.example.exs` to `config/dev.secret.exs` and fill in
  values; `config/dev.exs` imports it if present. `.worktreeinclude` lists this file
  so worktree tools copy it into each new worktree (a fresh worktree has only tracked
  files, so the secret would otherwise be missing and the server won't boot).

## Version control

- **jj (Jujutsu) is the primary local VCS**, colocated with git; **git stays
  authoritative for GitHub**. Publish with `jj git push` (plain `git push` also works).
  `.jj/` is git-ignored. Fetch with `jj git fetch`; `main` tracks `main@origin`.
- Use **`wt` (worktrunk)** for parallel worktrees — default config, no committed
  `.config/wt.toml`. Each worktree honors `PORT` (see Local development), and
  `.worktreeinclude` copies `config/dev.secret.exs` into new worktrees.
- This app is a git **submodule** of the `Tristan` project repo; when you advance it,
  bump the submodule pointer in `Tristan`. See the project-level `CLAUDE.md`.

## Commit messages

- Describe *what changed and why*. Subject in the imperative mood, ≤72 characters.
- The body explains the *why*, not a restatement of the diff.

## AI attribution

- End agent-written commit bodies with a `Co-Authored-By:` trailer naming the model,
  e.g. `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Skills

- **elixir-gotchas** — Elixir language traps, Mix task usage, ExUnit test mechanics.
- **phoenix-foundations** — Ecto, router scoping, HEEx syntax, form handling.
- **phoenix-liveview** — streams, JS hooks & colocated hooks, push_event, LiveView tests.
- **ui-and-assets** — layout/component conventions, Tailwind v4, bundling, design.
- **liveview-interactions** — deciding client (`JS` commands) vs server (`handle_event`).
