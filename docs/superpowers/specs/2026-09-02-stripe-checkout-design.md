# Stripe Checkout + Stripe Tax — pay an existing invoice

_2026-09-02_

## Context

Stripe credentials are wired (PR #1, merged): `config :music_studio, :stripe`, a
`MusicStudio.Billing.Stripe.health_check/0`, and keys in `.envrc` / GitHub secrets. The
`Billing` context already models `Invoice` (status/subtotal/total cents, CAD) and
`Payment` (`method` enum incl. `:card`, generic `reference`). This builds the first
paying slice: **let someone pay an existing invoice** via Stripe-hosted Checkout with
Stripe Tax calculating sales tax.

Approved decisions: public unguessable pay URL (no auth yet); a single summarizing line
item sent to Stripe; hand-rolled webhook signature verification (no `stripity_stripe`).

## Flow

1. Guardian opens `/invoices/:id/pay` (id = UUIDv7, unguessable).
2. "Pay now" → `POST` handled server-side → create a Stripe **Checkout Session**
   (`mode: payment`, `automatic_tax[enabled]: true`, one line item = invoice subtotal,
   `client_reference_id` = invoice id) → redirect to the session's hosted `url`.
3. Customer pays on Stripe's page → returns to `/invoices/:id/pay/success`.
4. **Fulfillment is driven by the webhook, not the redirect.** Stripe POSTs
   `checkout.session.completed` to `/webhooks/stripe`; we verify the signature, then
   record the `Payment`, set `invoice.tax_cents`, mark the invoice `:paid`, and record an
   analytics event. Idempotent on the Stripe session id.

## Components

**`MusicStudio.Billing.Stripe`** (extend)
- `create_checkout_session(invoice, opts)` → builds form params, `POST /v1/checkout/sessions`
  via `Req` (Stripe wants `application/x-www-form-urlencoded` with bracketed nested keys,
  e.g. `line_items[0][price_data][unit_amount]`, `automatic_tax[enabled]=true`). Returns
  `{:ok, %{id, url}}` / `{:error, reason}`. `success_url`/`cancel_url` passed in by the web layer.
  - Line item: `price_data` with `currency`, `product_data[name]` ("Invoice <short id>"),
    `unit_amount: invoice.subtotal_cents`, `tax_behavior: exclusive`; `quantity: 1`.
  - `billing_address_collection: required` (Stripe Tax needs an address).
- `construct_event(payload, sig_header)` → verify `Stripe-Signature` (parse `t=`/`v1=`,
  HMAC-SHA256 of `"#{t}.#{payload}"` with `webhook_secret`, `Plug.Crypto.secure_compare`,
  reject if timestamp skew > 5 min). Returns `{:ok, event_map}` / `{:error, reason}`.
  Uses `:crypto.mac/4` + `:crypto` — ~20 lines, fully tested.

**`MusicStudio.Billing.Checkout`** (new)
- `fulfill_session(session_map)` → in a `Repo.transaction`: look up invoice by
  `client_reference_id`; if a `Payment` with this `stripe_checkout_session_id` already
  exists, no-op `{:ok, :already_fulfilled}` (idempotency); else insert `Payment`
  (`method: :stripe`, `amount_cents: session["amount_total"]`, currency, `paid_at: now`,
  `reference: payment_intent`, stripe ids), update invoice (`tax_cents` from
  `total_details.amount_tax`, `total_cents: amount_total`, `status: :paid`), and
  `Analytics.record_event`. Returns `{:ok, payment}` / `{:error, reason}`.

**Web**
- `MusicStudioWeb.InvoicePayLive` — `/invoices/:id/pay` (shows invoice summary + Pay now),
  `/invoices/:id/pay/success`, `/invoices/:id/pay/cancel`. On "pay", builds success/cancel
  URLs (verified routes), calls `create_checkout_session`, `redirect(external: url)`.
  Uses `Layouts.app` + `ms-` classes. Handles already-paid + Stripe error states.
- `MusicStudioWeb.StripeWebhookController` — `POST /webhooks/stripe`. Reads the **raw
  body**, calls `construct_event`, and for `checkout.session.completed` calls
  `Checkout.fulfill_session`. Always returns `200` on a well-formed+verified event (even
  when already fulfilled) so Stripe stops retrying; `400` on bad signature.
- **Router:** both routes registered **before** the Beacon `"/"` catch-all (like
  `HomeLive`). Webhook in an `:api`-style pipeline (no CSRF/session).
- **Endpoint raw body:** add a body reader that caches the raw body for
  `/webhooks/stripe` only, so `Plug.Parsers` can still parse JSON while we keep the exact
  bytes for signature verification. (Custom `body_reader` in `Plug.Parsers` that stashes
  `raw_body` in conn assigns/private for that path.)

## Data model (one migration)

- `payments.method` enum: add `:stripe` (module `@methods` gains `:stripe`).
- `payments`: add `stripe_checkout_session_id :string` (unique index, partial: where not
  null) + `stripe_payment_intent_id :string`.
- `invoices`: add `tax_cents :integer, default: 0, null: false`.
- Update `Invoice`/`Payment` changesets to cast the new fields.

No separate `stripe_events` table — the unique session id gives idempotency for the one
event type we handle (YAGNI; add an events-log table if we later handle many event types).

## Money & tax

Tax is **exclusive**: Stripe adds tax on top of the invoice subtotal. Customer pays
`subtotal + tax` = Stripe's `amount_total`. We store `payment.amount_cents = amount_total`,
`invoice.tax_cents = total_details.amount_tax`, `invoice.total_cents = amount_total`.
All integer cents, currency from the invoice (CAD).

## Testing (all offline)

- `Req.Test` stub for the Stripe HTTP calls (config `:api_base_url` / plug already supports
  swapping): `create_checkout_session` builds correct params + parses `{id, url}`.
- `construct_event`: valid signature, bad signature, stale timestamp, malformed header.
- `Checkout.fulfill_session`: happy path side effects (payment + invoice + event),
  idempotency (second call is a no-op), unknown invoice.
- Controller test: verified event → 200 + fulfillment; bad signature → 400.
- LiveView test: pay page renders invoice; already-paid shows paid state.

## Out of scope (later)

Admin UI to create invoices; itemized (multi-line) Checkout; subscriptions; async payment
methods; refunds/disputes; the deployed prod webhook endpoint (needs `deploy-render`'s
public URL); enabling Stripe Tax registrations in the dashboard (user action).

## User prerequisites (not code)

- `stripe listen --forward-to localhost:4000/webhooks/stripe` → `whsec_…` into
  `STRIPE_WEBHOOK_SECRET` (CLI installed + authorized).
- Enable Stripe Tax (origin + registration) in the dashboard, or tax computes as $0.
