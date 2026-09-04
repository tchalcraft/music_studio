# Design: Documentation set + analytics/marketing stubs + Buzz roadmap

Date: 2026-09-04
Status: approved (scope confirmed with the user)

## Context

The music_studio app is live (Phoenix 1.7 + Beacon, Neon, Render, Resend, Stripe, Google
Calendar service account). The code and infra work, but the *understanding* is scattered
across code comments, `lessons.md`, `checkpoint.md`, and the operator's head. The owner wants:
(1) complete operator/developer documentation of the stack and workflows — with a clear answer
to "when/how do I use Beacon?"; (2) a customer user journey to seed UX work; (3) lightweight,
tested analytics + marketing stubs; and (4) a researched roadmap for using **Buzz**
(github.com/block/buzz) for student/teacher collaboration, agent-generated lesson plans, and
capturing live-session info — including how to configure Buzz via its API.

All four ship on branch `docs-and-stubs`. Docs live in `music_studio/docs/` (app repo, public,
travels with the code). No deploy from this work.

## Deliverables

### ① `docs/runbook.md` — Tech & services runbook (+ Beacon guide)
Operator/developer reference. Complements (does not duplicate) `README.md` and the root
`docs/architecture.md`. Sections:
- Architecture at a glance (request path; what's LiveView vs Beacon vs static).
- **Beacon: when & how to use it** (prominent, plain-language): `/cms` admin = edit CMS pages;
  hand-built LiveViews (`/`, `/book`, …) are code, NOT editable in `/cms`; the `beacon_site "/"`
  catch-all serves any other path from the DB; when/whether to "port" the home page into Beacon;
  **the `/cms`-has-no-auth gap to close before it matters.**
- Service-by-service (Phoenix/LiveView/Bandit, Beacon, Neon, Render, Porkbun, Resend, Stripe,
  Google Calendar): what it does / how it's configured (env-var NAMES, no secrets) / how to
  operate it (dev vs prod) / gotchas (pull from `lessons.md`).
- Deploy workflow (manual, pinned commit via Render API; migrate+seed+server; auto-deploy off).
- Local-dev quickstart; `mix precommit`; CI (`ci.yml` regression net, `bombadil.yml` manual).
- Correction to carry: **Cloudflare is NOT in the path** (Porkbun DNS → Render directly).

### ② `docs/user-journey.md` — Customer user journey
Journey maps to seed UX. Two personas:
- **Prospective student/parent:** discover (SEO/referral/word-of-mouth) → land on `/` → browse
  bio/lessons/rates → **inquire** (form → email) *or* **self-serve book** (`/book`) → confirmation
  email + calendar invite → attend lesson → follow-up / rebook / pay invoice.
- **Existing student:** manage booking (reschedule/cancel via `/book/manage/:token`), pay invoice
  (`/invoices/:id/pay`), rebook.
Each stage: goal, touchpoint (route/email), what the system does today, gaps & UX opportunities.
Grounded in real routes/flows; flag the two entry paths (inquiry vs. self-serve booking) that
currently coexist and any friction.

### ③ Analytics & marketing stubs — real code + `docs/analytics-and-marketing.md`
Data model already exists (`MusicStudio.Analytics.Event`, `record_event/1`, reporting views).
- **Analytics stubs:** emit events at the dormant hook points, matching the existing
  `side_effect`-wrapped `Analytics.record_event/1` pattern already used for `lesson_booked` /
  `series_booked` / `invoice_paid`. Add: `lead_created` (Leads.create_lead), `lead_converted`
  (CRM.convert_lead_to_student), `lesson_cancelled`, `lesson_rescheduled`, `series_paused`,
  `series_cancelled` (Scheduling), `invoice_created` (Billing). Best-effort, never fail the action.
- **Marketing/SEO scaffolding:** a meta/OG/Twitter-card partial in the root layout driven by
  per-LiveView assigns (meta_description, og_title/description/image, canonical); `sitemap.xml`
  route; `LocalBusiness`/`MusicSchool` JSON-LD structured data. Sensible defaults; no tracking
  pixels/consent banner yet (documented as future).
- **Tests** for new event emissions + SEO helpers; `mix precommit` green.
- Doc: event taxonomy (verb/subject conventions), how to query the reporting views, SEO setup,
  and what's deliberately deferred (GA/pixels/consent).

### ④ `docs/roadmap-buzz-collaboration.md` — Buzz roadmap + API-config guide (no code)
Vision + integration guide. **Verify specifics against github.com/block/buzz before asserting.**
- What Buzz is: self-hosted, **Nostr-protocol** collaborative workspace (Block, Rust); humans +
  AI agents as first-class members; channels, DMs, YAML workflows, voice huddles.
- Use-case fit (honest): channels for student/teacher ✅; agent-scripted lesson plans ✅;
  **session capture/transcription NOT built in ⚠️** — huddles carry live audio but recording +
  transcription need an external piece (e.g., Whisper/LiveKit).
- **How to configure/integrate via the API:** Nostr keypairs (nsec/npub) per user/agent; the
  HTTP-bridge (signed-event auth) vs. WebSocket paths; self-host stack (Postgres/Redis/S3-compatible);
  env-config sketch; how a Phoenix backend would talk to it. Concrete, but marked "verify".
- Differentiator vision: practice/lesson audio → transcription → **agent-generated personalized
  lesson plans & feedback** delivered in a channel.
- Phased roadmap: P1 channels (teacher↔student) → P2 agent lesson-plan workflows → P3 session-capture
  pipeline. Include "how to get live session info back" options (record huddle / upload practice
  audio / transcript via external service).
- **Consent & privacy section (required):** recording lessons — often with minors — needs explicit
  consent handling, retention policy, and access controls before any capture is built.

## Approach / execution
- Docs ①②④ drafted by parallel subagents (per the owner's "use subagents" preference), each briefed
  with the relevant research findings; the Buzz agent additionally web-verifies specifics.
- Code stubs ③ implemented directly against the existing context/notifier/test conventions, then
  `mix precommit` green.
- Author reviews all generated docs for accuracy before commit (owner is accountable for content).

## Verification
- `mix precommit` green (compile/format/credo/sobelow/tests incl. new event + SEO tests).
- Docs render, cross-link, and match the real code (routes, modules, env-var names).
- Buzz doc's factual claims verified against the repo (no hallucinated version/endpoint specifics).
- No deploy; commit on `docs-and-stubs`, leave for the owner's next batched deploy decision.

## Out of scope / deferred
- Building the Buzz integration (roadmap only).
- Tracking pixels / GA / cookie-consent (documented, not built).
- Porting the home page into Beacon (documented as an option in the runbook).
