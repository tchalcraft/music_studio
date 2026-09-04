# Analytics & Marketing

How the app records behavioral analytics and what SEO/marketing scaffolding exists. This
documents the current (stub-level) implementation and what's deliberately deferred.

---

## Analytics

### The event stream

Analytics is an **append-only event stream** plus SQL reporting views. The data model
(`MusicStudio.Analytics`, `MusicStudio.Analytics.Event`, table `events`) predates this doc;
it maps cleanly onto a lakehouse fact table.

Every event is a generic activity-stream row:

| Field | Meaning |
|-------|---------|
| `verb` (required) | what happened — snake_case, e.g. `lesson_booked` |
| `subject_type` (required) | the entity kind acted on — singular string, e.g. `"lesson"` |
| `subject_id` | the entity's id (stringified — works for UUIDv7 or the bigint lead) |
| `actor_type` / `actor_id` | who acted (optional) |
| `occurred_at` | event time (defaults to now) |
| `metadata` | free-form JSONB map |

Single write path: **`MusicStudio.Analytics.record_event/1`**. It's called **best-effort** at
domain hook points — a failed event insert is rescued/logged and never fails or crashes the
real action (bookings, payments, lead capture still succeed if analytics is down).

### Events emitted today

| Verb | Subject | Emitted from |
|------|---------|--------------|
| `lead_created` | `lead` | `Leads.create_lead/1` |
| `lead_converted` | `lead` | `CRM.convert_lead_to_student/2` |
| `lesson_booked` | `lesson` | `Scheduling.create_booking/1` |
| `series_booked` | `enrollment` | `Scheduling.create_series/*` |
| `lesson_cancelled` | `lesson` | `Scheduling.cancel_booking/1` |
| `lesson_rescheduled` | `lesson` | `Scheduling.reschedule_booking/2` |
| `series_paused` | `enrollment` | `Scheduling.pause_series/2` |
| `series_cancelled` | `enrollment` | `Scheduling.cancel_series/1` |
| `invoice_created` | `invoice` | `Billing.create_invoice/1` |
| `invoice_paid` | `invoice` | `Billing.Checkout.fulfill_session/1` |

Adding a new event = one best-effort `Analytics.record_event/1` call at the success path of
the operation, following the pattern already in those modules (Scheduling uses its
`side_effect/1` helper; Leads/CRM/Billing use a small local `best_effort_emit/1`).

### Reading the data

Two SQL views (created in migrations) give BI-shaped reads decoupled from the normalized tables:

- **`analytics_lesson_facts`** — lessons joined to students/teachers/instruments/offerings.
- **`analytics_funnel`** — leads grouped by source/status/instrument with conversion counts.

Accessors: `Analytics.lesson_facts/0`, `Analytics.funnel/0`, plus `list_events/1` and
`list_events_for/2` on the raw stream. The `events` table + views are the intended export
surface for a future lakehouse/BI pipeline (e.g. Databricks).

### Deliberately deferred

- No client-side tracking (page views, scroll, clicks) — events are server-side domain facts only.
- No third-party analytics (GA4, Mixpanel, Segment) and no tracking pixels.
- No cookie-consent banner (none needed while there's no client-side tracking; revisit if that changes).

---

## Marketing & SEO

### Per-page meta / Open Graph / Twitter — `MusicStudioWeb.SEO`

`lib/music_studio_web/components/seo.ex` renders, into every page's `<head>` (via the root
layout): a meta `description`, Open Graph (`og:title/description/type/url/image`), Twitter
`summary_large_image` card, and an optional canonical link. It ships **site-wide defaults**
(studio name, an in-person voice/piano/guitar description, the production URL, and the teacher
photo as the default `og:image`) so every page is covered, with **per-page overrides** via
assigns: set `@meta_description`, `@og_title`, `@og_image`, `@og_type`, or `@canonical_url` in a
LiveView's `mount`/`render` to override a default.

> Today only the defaults are wired; individual LiveViews don't set per-page overrides yet.
> That's the natural next step for page-specific SEO (e.g. a distinct description for `/book`).

### Structured data (JSON-LD)

The root layout also emits a `MusicSchool` schema.org block (name, description, url, image,
`areaServed` = White Rock, BC, `priceRange`), which helps search engines render a rich result.

### Sitemap & robots

**Beacon serves these automatically.** `beacon_site "/"` registers `/sitemap.xml`,
`/robots.txt`, and `/sitemap_index.xml` for the site — no custom route needed. Caveat: those
list published **Beacon** pages; the hand-built `/` and `/book` (LiveViews, not CMS pages) are
**not** in the sitemap yet. Closing that is a small follow-up — either extend Beacon's sitemap,
or the gap resolves naturally if/when the marketing pages move into Beacon (see the runbook's
"Beacon: when & how to use it").

### Lead capture (existing)

The inquiry form (`/`, `MusicStudio.Leads`) persists a `Lead` and best-effort emails the owner
(`Leads.Notifier`); it now also emits a `lead_created` analytics event. Known UX gaps (no
visitor confirmation email, no CRM auto-reply/tracking) are catalogued in
[`user-journey.md`](user-journey.md).

### Deliberately deferred

- Dynamic/generated OG images (currently the single teacher photo for all pages).
- Per-page meta overrides in each LiveView (defaults only for now).
- A custom sitemap that includes the hand-built pages (relying on Beacon's for now).
- Any paid-marketing / campaign attribution (the `analytics_funnel` view + `source` field on
  leads is the hook when that's wanted).
