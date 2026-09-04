# Tech & Services Runbook

This is the operator/developer reference for the music_studio app — a Phoenix 1.7 + Beacon CMS marketing site with an online booking system. It complements the [README](../README.md) (setup, stack overview) and complements the [project-level architecture](../../docs/architecture.md) (workspace topology, submodule structure). This runbook covers **what each service does, how to configure it, how to operate it, and gotchas learned in production**.

No deploy happens from reading this — it's purely informational. For deployment details, see **Deploy workflow** below.

---

## Architecture at a glance

### Request path: the routing model

The app runs on **Bandit** (HTTP server) → **Phoenix 1.7 Router** → hand-built **LiveView** pages + **Beacon CMS** catch-all.

```
Browser request
    ↓
MusicStudioWeb.Endpoint (Bandit, Phoenix 1.7)
    ↓ routes → /
    ├─ HomeLive (hand-built marketing page)
    │
    ├─ /book → BookingLive (online booking, calendar picker, slot selection)
    │
    ├─ /book/manage/:token → BookingManageLive (reschedule/cancel existing booking)
    │
    ├─ /invoices/:id/pay → InvoicePayLive (Stripe Checkout flow: show → success/cancel)
    │
    ├─ /webhooks/stripe → StripeWebhookController (raw-body signature-verified webhook)
    │
    ├─ /dev/* (dev-only: LiveDashboard, mailbox preview)
    │
    ├─ /cms → Beacon LiveAdmin (content management UI, no auth — see ⚠️ below)
    │
    └─ /* (catch-all) → Beacon site (CMS-rendered pages from the database)
```

### What is what

| Component | Location | Type | Purpose |
|-----------|----------|------|---------|
| **HomeLive** | `lib/music_studio_web/live/home_live.ex` | Hand-built LiveView | Marketing page (bio, rates, inquiry form). Currently owns exact `/`; intentionally NOT CMS-managed (yet). |
| **BookingLive** | `lib/music_studio_web/live/booking_live.ex` | Hand-built LiveView | Single + recurring lesson picker; real-time availability grid; instant booking + confirmation email. |
| **BookingManageLive** | `lib/music_studio_web/live/booking_manage_live.ex` | Hand-built LiveView | Reschedule/cancel existing bookings via token (no login). |
| **InvoicePayLive** | `lib/music_studio_web/live/invoice_pay_live.ex` | Hand-built LiveView | Stripe Checkout flow (show session, success/cancel paths). |
| **Beacon site** | `beacon` + `beacon_live_admin` (deps) | CMS engine | Database-backed pages, layouts, components. Served at catch-all `/*`. Admin UI at `/cms`. |
| **StripeWebhookController** | `lib/music_studio_web/controllers/stripe_webhook_controller.ex` | API endpoint | Raw-body signature-verified webhook: confirms checkout sessions → records payments, fulfills invoices. |

### Code vs. CMS: the key distinction

- **Hand-built LiveViews** (`/`, `/book`, `/book/manage/:token`, `/invoices/:id/pay`) live in `lib/music_studio_web/live/` — they are **code**, reviewed in PRs, deployed in git commits. They are **NOT editable in `/cms`**.
- **Beacon CMS pages** are in the database; any path **not** claimed above (and not under `/dev`, `/cms`, `/webhooks`) is served by the `beacon_site "/"` catch-all. These pages are editable in the `/cms` admin UI **without a code deploy**. This is where custom marketing pages (FAQ, testimonials, etc.) live.

**The home page is currently hand-built** (HomeLive at `/`). To move it to the CMS: build a Beacon page template in `/cms` (admin UI), then flip the router to remove the `live "/"` route and let Beacon's catch-all own `/` instead.

---

## Beacon: when & how to use it

### What Beacon is

Beacon is a **database-backed page/layout/component CMS for Phoenix apps**. Pages, layouts, and components are stored in the database (not git), editable via an admin UI (`/cms`), and compiled to HTML/CSS/JS at runtime or on first request.

In this app:
- **Layouts** = page frame (header, footer, navigation).
- **Components** = reusable chunks (hero section, call-to-action, etc.).
- **Pages** = full pages built from layouts + components.
- All live in the **same database** as the booking system (via `MusicStudio.Repo`).

### Where to use Beacon ✅

- **Custom marketing pages**: FAQ, testimonials, blog posts, press kit — anything that needs to change without a deploy.
- **One-off landing pages**: for campaigns, special offers, events.
- **Error pages**: 404, 500 templates.

### Where NOT to use Beacon ❌

- **The booking flow** (`/book`, `/book/manage/:token`): these need real-time state, WebSocket communication, and form validation. Keep these as hand-built LiveViews.
- **Sensitive workflows** (payments, admin features): build these as LiveViews with proper auth.
- **Anything requiring custom logic**: Beacon is for static/semi-static content. Complex interactions live in Elixir.

### How to add a CMS page

1. **Go to `/cms`** → Beacon admin (currently no login; anyone reaching it can edit).
2. **Layouts**: create a layout (`Header + Body + Footer` template; HEEx syntax).
3. **Components**: create reusable chunks; use in layouts/pages.
4. **Pages**: create a page (pick a layout, compose components, add content, assign a path — e.g. `/faq`).
5. **Publish**: the page is live immediately at the assigned path (unless you're in draft mode).

See the [Beacon docs](https://github.com/BeaconCMS/beacon) for template syntax and advanced features.

### ⚠️ SECURITY: `/cms` has NO authentication

**Anyone who reaches `/cms` can create, edit, and delete pages.** Before this CMS matters for sensitive content, add auth. Options:
- **Quick (plug):** a `Plug.BasicAuth` middleware on the `:beacon_admin` pipeline (static credentials).
- **Proper (context):** a `MusicStudio.Admin` context with password hashing, session tracking, and operator audit logs.

For now, `/cms` is a development/demo feature. Keep it in mind when opening the site to the public.

### Beacon + Neon + config

Beacon stores everything in the database (Neon in dev/prod). The site config is in `config/config.exs`:

```elixir
config :beacon, music_studio: [
  site: :music_studio,
  repo: MusicStudio.Repo,          # ← same repo as booking data
  endpoint: MusicStudioWeb.Endpoint,
  router: MusicStudioWeb.Router,
  css_compiler: MusicStudioWeb.BeaconRuntimeCSS,  # ← Tailwind v4 compiler (Beacon expects v3)
  page_warming: :none               # ← lazy compile (free-tier CPU constraint)
]
```

The `:css_compiler` is custom because **Beacon 0.5.1 expects Tailwind v3**, but this app runs **Tailwind v4**. The `MusicStudioWeb.BeaconRuntimeCSS` module runs Tailwind v4 over Beacon's template content so pages share the design-token styling (the `ms-` classes). It falls back to basic CSS if compilation fails, so the site always boots.

### Beacon also auto-serves SEO endpoints

`beacon_site "/"` automatically registers **`/sitemap.xml`**, **`/robots.txt`**, and **`/sitemap_index.xml`** for the site (listing published CMS pages) — you don't add a route for these. Caveat: the hand-built `/` and `/book` are **not** Beacon pages, so they aren't in that sitemap yet. Per-page meta/OG tags and JSON-LD for the hand-built pages come from `MusicStudioWeb.SEO` instead (see `docs/analytics-and-marketing.md`).

---

## Service-by-service

### Phoenix 1.7 + LiveView 1.2 + Bandit

**What it is**: HTTP server (`Bandit`), request router (`Phoenix.Router`), and real-time page updates (`Phoenix.LiveView`). The web framework holding everything together.

**Pinned versions**:
- **Phoenix 1.7** (not 1.8) — **Beacon 0.5.1 uses a Phoenix private API removed in 1.8**, so the entire app is constrained to 1.7. See `lessons.md` (2026-08-30) for the full dependency saga.
- **LiveView 1.2** — compatible with Phoenix 1.7; used for the hand-built pages (`/`, `/book`, etc.).
- **Bandit `~> 1.5`** — the HTTP server (`mix.exs`), wired via `adapter: Bandit.PhoenixAdapter`.

**Configure**:
- Compile-time: `config/config.exs` sets `adapter: Bandit.PhoenixAdapter`, port (default 4000), and LiveView signing salt.
- Runtime (prod): `config/runtime.exs` reads `PORT` (default 4000) and `PHX_SERVER=true` (enable server mode in release).

**Dev**:
```bash
mix phx.server          # Boots on localhost:4000, live-reloads on file changes
PORT=4001 mix phx.server  # Run multiple servers (in separate worktrees) on different ports
```

**Prod**:
- Runs in the Docker container as an **OTP release** (`bin/music_studio start` from Render).
- `PHX_SERVER=true` and `PORT=4000` are set in the environment.
- Listens on `0.0.0.0:4000` inside the container; Render reverse-proxies to the public HTTPS endpoint.

**Gotchas**:
- LiveView needs `check_origin: [...]` for CSRF prevention. In prod, `config/runtime.exs` sets this to the public host(s) — if you add a custom domain, update that list.
- The app uses **LiveView colocated hooks** (JS in `assets/js/app.js` is scoped per component). The `mix compile` step must run **before** `mix assets.deploy`, or the asset pipeline won't find them (see `Dockerfile` for the correct order).

---

### Neon Postgres

**What it is**: PostgreSQL hosted on **Neon**, a Postgres cloud with copy-on-write branching. The app uses one logical Postgres instance (the Neon free tier) split into **dev** and **prod** branches so the app doesn't accidentally overwrite production data during development.

**Credentials**:
- **Dev**: `DATABASE_URL` env var pointing to the dev branch. Set it in the project `.envrc` (git-ignored, loaded by `direnv allow`).
- **Prod**: `DATABASE_URL` env var (Render secret) pointing to the prod branch. Provisioned at https://console.neon.tech.

**Configure**:
- **Dev** (`config/dev.exs`): uses `DATABASE_URL` if set, else falls back to local Postgres.
- **Prod** (`config/runtime.exs`): requires `DATABASE_URL`, applies Neon-specific Postgres settings:
  ```elixir
  ssl: [verify: :verify_none],   # ← Neon's cert is self-signed; skip verification
  prepare: :unnamed,             # ← PgBouncer in transaction mode; named prepared statements cause conflicts
  pool_size: 5,                  # ← Free tier: keep it small
  ```

**URLs**:
- **Pooled endpoint** (`-pooler` in the URL) — use for short-lived connections and web apps. Neon uses PgBouncer in transaction mode, so `:unnamed` prepared statements are required.
- **Direct endpoint** (no `-pooler`) — for long-running connections (not used here).

**Dev usage**:
```bash
# Set DATABASE_URL from .envrc, then:
mix ecto.migrate      # Migrates the dev branch
mix ecto.rollback     # Rolls back one migration
mix ecto.reset        # Drops, creates, migrates fresh

# Query the current database:
psql "$DATABASE_URL"  # Connect to whatever DATABASE_URL points to
```

**Prod**:
- Migrations run automatically on boot (Dockerfile `CMD: bin/migrate && bin/seed && bin/server`).
- Schema is **append-only events** (immutable lesson/payment facts) + CMS content (Beacon) + reference data (catalog). No custom backups needed — Neon's free tier includes automatic snapshots.

**Gotchas**:
- **Database URL override gotcha**: `direnv exec env DATABASE_URL="..." mix run …` doesn't work as expected — `direnv exec` loads `.envrc` **after** the inline `DATABASE_URL`, overriding it. Correct form: `direnv exec env DATABASE_URL="..." mise exec -- mix run …` (inline **after** `direnv`). Always verify which database you're connected to by logging the endpoint. See `lessons.md` (2026-09-04).
- **View-blocked alters**: if a Postgres view references a column and you try to `ALTER TABLE … MODIFY column_type`, the alter fails because the view depends on it. Workaround: use raw `ALTER TABLE … ALTER COLUMN … DROP NOT NULL` (changes only the constraint) or drop/recreate the view. Migrations in this app use raw SQL for nullability changes on viewed columns.

---

### Render (deployment + hosting)

**What it is**: A cloud platform (free tier) that runs the **OTP release** (compiled Elixir app) in a Docker container, with the database on Neon.

**Configuration** (`render.yaml` Blueprint spec):
```yaml
services:
  - type: web
    name: music-studio
    runtime: docker              # ← Run a Dockerfile
    plan: free                   # ← Free tier: one small container, sleeps after 15 min idle
    region: oregon
    dockerfilePath: ./Dockerfile
    envVars:
      - PHX_SERVER=true
      - POOL_SIZE=5              # ← Small; keep DB connections low
      - DATABASE_URL             # ← Neon prod branch (set in Render dashboard)
      - SECRET_KEY_BASE          # ← Generated once, never rotate (breaks encrypted sessions)
      - PHX_HOST                 # ← Your public domain (e.g. tristanchalcraftmusic.com)
      - INQUIRY_TO_EMAIL / INQUIRY_FROM_EMAIL
      - RESEND_API_KEY
      - STRIPE_SECRET_KEY        # ← Required at boot (runtime.exs raises without it)
      - STRIPE_PUBLISHABLE_KEY / STRIPE_WEBHOOK_SECRET
      - GOOGLE_SERVICE_ACCOUNT_KEY / GOOGLE_AVAILABILITY_CALENDAR_ID (optional)
```

**Secrets** (set in Render dashboard, NOT committed):
- `DATABASE_URL`: pooled Neon connection string for prod branch.
- `SECRET_KEY_BASE`: generated once (e.g. `mix phx.gen.secret`), never rotate.
- `PHX_HOST`: public domain (e.g. `tristanchalcraftmusic.com`).
- Email, Stripe, Google Calendar keys: see below.

**Dev vs. Prod**:
- **Dev**: local Docker build or `mix phx.server` (Neon dev branch).
- **Prod**: Render runs the `Dockerfile` → compiles OTP release → boots with migrations + seed + server.

**Boot sequence** (Docker `CMD`):
```bash
bin/migrate && bin/seed && bin/server
```
- `migrate` — runs pending migrations (idempotent).
- `seed` — runs `priv/repo/seeds.exs` (idempotent catalog seed; booking data is never seeded).
- `server` — starts the Bandit HTTP server on port 4000.

This order ensures the database is ready and the app always has reference data (instruments, teacher profile, etc.) — see `lessons.md` (2026-09-04, "Prod booking was broken").

**Gotchas**:
- **Free tier sleeps**: after ~15 min idle, the service goes to sleep. First request is slow (~30s). Accepted trade-off for free hosting.
- **Auto-deploy OFF**: deployments are **manual** (see **Deploy workflow** below). A push to `main` does NOT auto-deploy; you trigger it via the Render API.
- **Migrations + seeding**: the free tier has one instance, so there's no migration race. Seeding is **required** — the booking page queries the catalog live (instruments, offerings, teacher) from the database. Without the seed, no one can book. (This was a prod incident; see `lessons.md`.)
- **Free-tier CPU**: Beacon's boot population (initial compile of pages, layouts, components) times out on weak CPU. Set `page_warming: :none` in the Beacon config to compile pages lazily on first request instead. See `config/config.exs` and `lessons.md` (2026-08-30).

---

### Porkbun (DNS)

**What it is**: Domain registrar for `tristanchalcraftmusic.com`.

**Setup**:
- Domain registered at Porkbun; DNS records stay at Porkbun — an **apex `ALIAS`** and a **`www` `CNAME`**, both pointing at the Render onrender host. Render issues the TLS cert automatically once the records verify.
- **NO Cloudflare in the path** — DNS points directly from Porkbun → Render. This simplifies the setup (no reverse-proxy config, no cache invalidation) and keeps TLS termination at Render.

**Dev**: use `localhost:4000` or `.local` domains (not Porkbun).

**Prod**:
- `PHX_HOST` = `tristanchalcraftmusic.com` (set in Render).
- LiveView `check_origin: ["https://tristanchalcraftmusic.com", "https://www.tristanchalcraftmusic.com"]` (configured in `runtime.exs`).

**Gotchas**: none noted; DNS is straightforward here.

---

### Resend (transactional email)

**What it is**: Transactional email service (like SendGrid, but simpler). Sends inquiry confirmations and booking notifications.

**Credentials**:
- **API key**: `RESEND_API_KEY` env var (set in Render secrets, local `.envrc` for dev).
- **From address**: must be verified in Resend console. Currently configured as `INQUIRY_FROM_EMAIL` / `BOOKING_FROM_EMAIL` (env vars).

**Configure**:
- **Dev** (`config/dev.exs`): uses `Swoosh.Adapters.Local` (emails land in browser at `/dev/mailbox`).
- **Prod** (`config/runtime.exs`): if `RESEND_API_KEY` is set, switches to `Swoosh.Adapters.Resend`.

**Usage**:
- **Inquiry notifications** (`MusicStudio.Leads.Notifier`): when a visitor fills the inquiry form, an email goes to the teacher.
- **Booking confirmations** (`MusicStudio.Scheduling.Notifier`): when a lesson is booked, a confirmation + `.ics` file go to the student; a notification goes to the teacher.
- **Best-effort**: if email send fails, it's logged but doesn't crash the page. Leads and bookings persist to the database regardless.

**Dev**:
```bash
# Resend is configured in config/dev.secret.exs (git-ignored)
# Use the test key from https://resend.com/keys
export RESEND_API_KEY="re_..."  # in .envrc
mix phx.server
# Visit localhost:4000/dev/mailbox to see emails
```

**Prod**:
- From address (`no-reply@musicstudio.local`) must be Resend-verified OR an email domain you control + verify at Resend.
- Current config defaults to `musicstudio.local` (a placeholder). Update `INQUIRY_FROM_EMAIL` / `BOOKING_FROM_EMAIL` to a real, verified address.

**Gotchas**:
- **From address must be verified**: Resend rejects sends from unverified addresses.
- **API key in .envrc**: local dev secrets live in `.envrc` (direnv), not git. Worktrees copy `config/dev.secret.exs` but not `.envrc` by default — add `.envrc` to `.worktreeinclude` if you need email in a worktree.

---

### Stripe (payments)

**What it is**: Payment processor. Handles checkout (single-use sessions), invoicing, and webhook callbacks.

**Flow**:
1. **Checkout session** (`/invoices/:id/pay`): student clicks "Pay invoice", LiveView calls `Stripe.create_checkout_session/2`, gets back a hosted Checkout URL, redirects the student there.
2. **Payment** (at Stripe): student enters card details in Stripe's hosted form.
3. **Webhook** (`/webhooks/stripe`): Stripe POSTs a signed event; `StripeWebhookController` verifies the signature and fulfills the invoice (records the payment, marks the invoice paid).

**Credentials**:
- **Secret key** (`STRIPE_SECRET_KEY`): required at boot (prod raises without it). Use test key (`sk_test_…`) in dev/staging, live key (`sk_live_…`) in production.
- **Publishable key** (`STRIPE_PUBLISHABLE_KEY`): optional, used by client-side code (not yet implemented).
- **Webhook secret** (`STRIPE_WEBHOOK_SECRET`): required once webhooks are live. Set it in Render secrets after configuring the endpoint at Stripe.

**Configure**:
- **Compile-time defaults** (`config/config.exs`):
  ```elixir
  config :music_studio, :stripe,
    secret_key: nil,
    publishable_key: nil,
    webhook_secret: nil,
    api_base_url: "https://api.stripe.com"
  ```
- **Dev** (`config/dev.secret.exs`): read from `STRIPE_*` env vars (in `.envrc`).
- **Prod** (`config/runtime.exs`): read from `STRIPE_*` env vars (in Render secrets).

**Client** (`MusicStudio.Billing.Stripe`):
- Uses `Req` (HTTP client already a dep); no `stripity_stripe` gem.
- `health_check/0` — confirms the key reaches Stripe (`GET /v1/account`).
- `create_checkout_session/2` — creates a hosted session.
- `construct_event/2` — verifies webhook signature (HMAC-SHA256, constant-time compare) and decodes the payload.

**Dev**:
```bash
# Set STRIPE_SECRET_KEY in .envrc (test key from https://dashboard.stripe.com/apikeys)
export STRIPE_SECRET_KEY="sk_test_…"
mix phx.server

# To test the webhook locally:
stripe listen --forward-to localhost:4000/webhooks/stripe
# (Set the forwarded webhook secret in .envrc as STRIPE_WEBHOOK_SECRET)

# Or stub Stripe in tests:
config :music_studio, :stripe, req_plug: {Req.Test, MusicStudio.Billing.Stripe}
```

**Prod**:
- Live keys set in Render secrets.
- Webhook URL registered at Stripe: `https://tristanchalcraftmusic.com/webhooks/stripe`.
- Webhook endpoint re-signs with `STRIPE_WEBHOOK_SECRET`; store that secret in Render after Stripe generates it.

**Webhook signature verification**:
- Raw body must be cached (Plug.Parsers consumes it). `MusicStudioWeb.CacheBodyReader` stashes it in `conn.assigns.raw_body`.
- Verify: parse `Stripe-Signature` header (`t=timestamp, v1=signatures`), HMAC-SHA256 of `"#{t}.#{payload}"`, constant-time compare, reject if `|now - t| > 300s`.

**Gotchas**:
- **Raw body needed**: webhook verification fails silently if the body was consumed. Use the `CacheBodyReader` (wired in endpoint config).
- **Timestamp replay protection**: signatures older than 5 min are rejected. Clock skew can cause issues; ensure server time is in sync (NTP).
- **Idempotent fulfillment**: a unique constraint on `payments.stripe_checkout_session_id` (where not null) + a pre-check ensures that a retry of a webhook (Stripe retries failed webhooks) doesn't double-fulfill.
- **Worktree secrets**: `config/dev.secret.exs` is per-worktree (git-ignored). Each new worktree needs Stripe keys if you want to test locally. Copy from the main checkout or add `.envrc` to `.worktreeinclude`.

---

### Google Calendar (optional, writes only)

**What it is**: Google Calendar (cloud calendar). The app **writes** booked lessons to a shared calendar (read-only for the app) using a **service account** — no OAuth flow, no user consent.

**Setup**:
1. Create a **service account** at Google Cloud Console (https://console.cloud.google.com/iam-admin/serviceaccounts).
2. Generate a JSON key for the service account.
3. Create a calendar or use an existing one; **share it with the service account's email** (e.g., `music-studio@project.iam.gserviceaccount.com`) with "Make changes to events" permission.
4. Configure the app with the key and calendar IDs.

**Credentials**:
- **Service account key** (`GOOGLE_SERVICE_ACCOUNT_KEY`): JSON string (the key file exported from Google Cloud), base64-encoded or raw.
- **Calendar IDs**: 
  - `GOOGLE_AVAILABILITY_CALENDAR_ID`: the calendar the app writes lesson events to (it's also the default write `target` when `GOOGLE_TARGET_CALENDAR_ID` is unset). Despite the name, availability is NOT read from it today — availability is app-defined (working hours minus DB bookings). Reading busy-times from it is a future feature.
  - `GOOGLE_TARGET_CALENDAR_ID`: overrides the calendar where the app writes booked lessons. Defaults to the availability calendar if not set.

**Configure**:
- **Dev** (`config/dev.secret.exs`): load from `.envrc`.
- **Prod** (`config/runtime.exs`): load from env vars. Both optional — the app works without them (bookings succeed, just don't write to Google Calendar).

**Usage**:
- **Booking**: when a lesson is booked, `MusicStudio.Scheduling` writes an event to the target calendar via `GoogleCalendar.insert_event/2` (best-effort, wrapped in `side_effect/1`; a failure is logged but never fails the booking). The `Notifier` separately sends the confirmation email — calendar writes and email delivery are distinct paths.
- **Cancellation / reschedule**: **implemented** — the event is deleted (`GoogleCalendar.delete_event/2`) on cancel and updated (`GoogleCalendar.update_event/3`) on reschedule, both best-effort.

**Dev**:
```bash
# Create a test service account and calendar at Google Cloud.
# Export the JSON key, then add to .envrc:
export GOOGLE_SERVICE_ACCOUNT_KEY='{"type":"service_account","project_id":"...",...}'
export GOOGLE_TARGET_CALENDAR_ID="calendar-id@example.com"

# Boot the app; on booking, the event appears in the calendar.
```

**Prod**: set env vars in Render secrets.

**Gotchas**:
- **Service account email must have calendar access**: share the calendar with the service account's email (from the JSON key, field `client_email`), not the project ID.
- **Write-only**: the app writes events, not reads them. Availability is app-defined (working hours, booked lessons from the database), not fetched from Google. Reading is a future feature.
- **Best-effort**: if the Google API is down, the booking still succeeds; the event just doesn't appear. Always check logs.
- **Timezone-aware**: events are written with the configured `studio_timezone` (America/Vancouver).

---

### Scheduling (availability, booking constraints)

**What it is**: The logic that defines when lessons can be booked (working hours, no double-booking, minimum notice, etc.) and writes to Google Calendar + sends confirmations.

**Configuration** (`config :music_studio, MusicStudio.Scheduling`):
```elixir
studio_timezone: "America/Vancouver",        # ← All slots in this TZ
slot_grid_minutes: 30,                       # ← 30-min slots
buffer_minutes: 15,                          # ← 15-min gap between lessons
min_notice_minutes: 24 * 60,                 # ← 24-hour advance notice
working_days: [1, 2, 3, 4, 5],              # ← Mon–Fri (1=Monday)
working_start: ~T[14:00:00],                # ← 2:00 PM
working_end: ~T[21:00:00],                  # ← 9:00 PM
```

**Gotchas** (from `lessons.md`):
- **UTC day-boundary**: since `working_end` is 9 PM PT (which is the next day in UTC), per-day queries must span UTC boundaries. `Availability.compute` handles the overlap check precisely, so query windows can be wider without risk.
- **Single/recurring**: single lessons are booked as `Lesson` records; recurring series are `Series` records (rolled out weekly through Jun 30, with pause/skip options).

---

## Deploy workflow

**Manual pinned commits** — no auto-deploy. Every production deployment is:

1. **Choose a commit** (usually a tested, merged PR on `main`).
2. **Trigger Render** with the commit SHA (via the Render API or dashboard).
3. **Render builds** the Docker image, runs migrations + seed, and boots.
4. **Test** the live site (smoke test via `/` or the booking flow).

### Via Render dashboard (interactive)

1. Go to Render dashboard → select the `music-studio` service.
2. Click "**Deploy**" → choose a branch (`main`) or commit SHA.
3. Wait for the build to complete (~5 min).
4. Click the logs to monitor: builder, runner, boot (migrate → seed → server start).

### Via Render API (scripted)

```bash
SERVICE_ID="..."  # Available in Render dashboard
API_KEY="..."     # Your Render API key (from account settings)
COMMIT_SHA="..."  # The commit to deploy

curl -X POST "https://api.render.com/v1/services/${SERVICE_ID}/deploys" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"commitId\":\"${COMMIT_SHA}\"}"

# Poll for completion:
curl "https://api.render.com/v1/services/${SERVICE_ID}/deploys?limit=1" \
  -H "Authorization: Bearer ${API_KEY}" | jq '.deploys[0].status'
# Returns: "created", "build_in_progress", "build_failed", "deploy_in_progress", "deployed", "deploy_failed"
```

See [Render API docs](https://render.com/docs/api-reference#get-service-deploys) for full details.

### Post-deploy checklist

1. **Check status**: is the service running (green) or crashed?
2. **Visit the site**: https://tristanchalcraftmusic.com → does it load?
3. **Test booking flow**: go through the booking flow once (don't book yourself, but confirm the page renders and the calendar shows slots).
4. **Check logs**: Render dashboard → logs tab → look for errors (especially `Beacon.Boot`, migrations, seed).
5. **Database**: ensure migrations ran (check `schema_migrations` table in prod) and catalog was seeded (should see instruments in the booking page).

---

## Local dev quickstart

### Prerequisites

**Toolchain** (managed by `mise`):
- **Elixir 1.18.4 / OTP 28** (pinned in `.tool-versions`).
- **Node.js 20+** (for `esbuild`, `tailwind` if building locally; Nix Postgres if using a local DB).

Install `mise` once globally, then:
```bash
cd music_studio
mise install  # Reads .tool-versions, installs Elixir/OTP/Node
```

### Setup

```bash
cd music_studio

# Copy the local dev secrets template and fill in values (Google, Resend, Stripe keys from `.envrc`)
cp config/dev.secret.example.exs config/dev.secret.exs
# Edit config/dev.secret.exs with your keys

# Install deps, create/migrate DB, seed catalog, build assets
mix setup

# Start the server
mix phx.server  # Boots on localhost:4000

# In another terminal, test (optional)
mix test        # Runs the full test suite
```

### Database

**Dev database** is Neon (postgres via `DATABASE_URL` from `.envrc`, direnv):
```bash
# Set up direnv (one time)
direnv allow        # Loads .envrc (defines DATABASE_URL)

# Then use Ecto normally
mix ecto.migrate    # Runs pending migrations
mix ecto.rollback   # Rolls back one
mix ecto.reset      # Drops, creates, migrates fresh
```

Alternatively, **use a local Postgres** (install via Nix):
```bash
# Ensure local Postgres is running and has a `postgres` superuser/role
psql -U postgres postgres  # Should connect

# Create the database
createdb music_studio_dev

# Migrate
mix ecto.migrate
```

### Code quality gate

Before pushing:
```bash
mix precommit
```

This runs (in order): compile (warnings-as-errors), skills.check, format, gettext, Credo (strict), Sobelow, and tests. If any step fails, the rest don't run (exit early). **All must pass** before pushing to `main`.

### Multiple worktrees

To run multiple instances on different ports (e.g., testing on one branch while working on another):

```bash
# Main checkout: music_studio/
PORT=4000 mix phx.server

# In another directory, create a git worktree (new checkout on a different branch)
cd ..
git worktree add ../music_studio_wt --track origin/feature-xyz

# In the worktree
cd ../music_studio_wt
PORT=4001 mix phx.server  # Runs on 4001, doesn't interfere
```

**Worktree note**: `.worktreeinclude` lists files that are copied into new worktrees. Currently: `config/dev.secret.exs`. If you add files that should propagate to worktrees, update that list.

---

## CI (Continuous Integration)

### GitHub Actions workflows

Located in `.github/workflows/`:

#### `ci.yml` — Regression net (every push/PR)

**Trigger**: push or PR to `main`.

**What it does**:
- Spins up Ubuntu, Elixir 1.18.4/OTP 28, and Postgres 16 (as a service).
- Runs `mix precommit` (compile, format, Credo, Sobelow, tests, property tests).
- Caches `deps/` and `_build/` between runs.

**Result**:
- ✅ **Green** = all gates pass (safe to merge).
- ❌ **Red** = a gate failed (compile, Credo, Sobelow, or tests). Check the logs for the first failure; often it's an early gate (compile, Credo) that blocks tests.

**NOT a deploy gate**: the workflow runs but does **not** trigger a Render deploy. Deploys are manual.

#### `bombadil.yml` — Browser smoke tests (manual + weekly)

**Trigger**: manual (`Actions` → `Run workflow`) or scheduled Monday 13:00 UTC.

**What it does**:
- Installs Node 20 on Ubuntu.
- Runs Bombadil (property-based browser testing) against the live site at `https://tristanchalcraftmusic.com` (or a custom origin).
- Explores the inquiry + booking flows, checking for crashes, missing elements, and flow invariants.

**Result**: artifacts (JSON report) available in `Actions` → run details.

**Why CI?**: The Databricks corporate network blocks both npm (esbuild binary) and the `tristanchalcraftmusic.com` domain (newly-registered). GitHub runners have internet access, so Bombadil runs there.

**Local validation** (optional, if you have internet access):
```bash
cd e2e
npm install
npx bombadil browser test --time-limit=2m https://tristanchalcraftmusic.com
```

---

## Appendix: Quick reference

### Key files

| File | Purpose |
|------|---------|
| `lib/music_studio_web/router.ex` | Route definitions (hand-built pages, Beacon catch-all, webhooks) |
| `config/config.exs` | Compile-time defaults (Beacon, Tailwind, esbuild, scheduling) |
| `config/runtime.exs` | Prod runtime config (secrets from env vars) |
| `config/dev.secret.exs` | Local dev secrets (git-ignored; copy from `dev.secret.example.exs`) |
| `config/dev.exs` | Dev-only config (LiveReload, local DB) |
| `Dockerfile` | OTP release container (Elixir 1.18.4, Debian Bookworm) |
| `render.yaml` | Render Blueprint (one free web service) |
| `.tool-versions` | Toolchain pinning (Elixir 1.18.4, OTP 28, Node 20) |
| `mix.exs` | Mix project definition (deps, tasks, precommit alias) |
| `lib/music_studio_web/beacon_runtime_css.ex` | Tailwind v4 CSS compiler for Beacon |
| `lib/music_studio/scheduling/` | Availability, booking, Google Calendar, notifiers |
| `lib/music_studio/billing/stripe.ex` | Stripe client (health check, checkout, webhooks) |

### Environment variables (Render secrets)

| Var | Required? | Use |
|-----|-----------|-----|
| `DATABASE_URL` | Yes | Neon pooled connection string (prod branch) |
| `SECRET_KEY_BASE` | Yes | Generated once, never rotate (cookie signing) |
| `PHX_HOST` | Yes | Public domain (tristanchalcraftmusic.com) |
| `PHX_SERVER` | Yes | "true" (enable server mode in release) |
| `POOL_SIZE` | No | Default 10; set to 5 for free tier |
| `PORT` | No | Default 4000 |
| `INQUIRY_TO_EMAIL` | No | Where inquiry form emails go |
| `INQUIRY_FROM_EMAIL` | No | From address (must be Resend-verified) |
| `RESEND_API_KEY` | No | Transactional email; optional (best-effort if unset) |
| `STRIPE_SECRET_KEY` | Yes | Required at boot; use test key (`sk_test_…`) |
| `STRIPE_PUBLISHABLE_KEY` | No | Client-side key (not yet used) |
| `STRIPE_WEBHOOK_SECRET` | No | Set after configuring webhook at Stripe |
| `GOOGLE_SERVICE_ACCOUNT_KEY` | No | Service account JSON key (optional; bookings work without it) |
| `GOOGLE_TARGET_CALENDAR_ID` | No | Calendar to write events to (optional) |
| `GOOGLE_AVAILABILITY_CALENDAR_ID` | No | Availability calendar (optional, currently unused) |

---

## Resources

- **Beacon**: https://github.com/BeaconCMS/beacon
- **Phoenix**: https://www.phoenixframework.org/
- **Phoenix deployment**: https://hexdocs.pm/phoenix/deployment.html
- **Render**: https://render.com/docs
- **Neon**: https://neon.tech/docs
- **Stripe API**: https://stripe.com/docs/api
- **Google Calendar API**: https://developers.google.com/calendar/api
- **Project lessons**: `/lessons.md` (2026-08 to 2026-09 entries detail Beacon setup, Stripe, availability, CI)
