# Design: Booking confirmation email + calendar invite + single-lesson reschedule

Date: 2026-09-05
Status: approved (scope confirmed with the user)
Closes: #15 (email flow), #11 (organizer placeholder). Also adds a regression test for the
already-fixed #6 (plaintext manage link) so it can be closed.

## Context

The booking system is live. After a student books, `MusicStudio.Scheduling.Notifier` sends a
branded HTML+text confirmation with an `.ics` attachment, and (best-effort) writes a Google
Calendar event via the service account. Tristan reviewed the deployed emails/invites and filed
#15 and #11. The problems are all in the **confirmation email + calendar invite** and in the
**manage-booking** experience:

- The calendar invite's `ORGANIZER` is the seeded placeholder `tristan@example.com` (#11) —
  students see it. It should present as **Tristan Chalcraft Music**.
- The location is the placeholder string `"Studio"` (email "Where", ICS `LOCATION`, the
  Google quick-add URL). It should be the real studio address.
- The email/invite don't distinguish a **single** lesson from a **recurring series**.
- The "manage" link is buried in plaintext; it should be a clear **"Modify" button** that
  takes the student to the site to **cancel or pick a new time**. The reschedule *backend*
  (`Scheduling.reschedule_booking/2`) exists, but the manage page has **no "pick a new time"
  UI** — only cancel (single) and skip/pause/cancel (series).

All work ships on branch **`fix-email-flow`** (its own `wt` worktree). App changes only; PR to
`music_studio`, CI green, then batched for the next manual Render deploy. No migrations.

## Relevant code (verified on deployed `d4ed54f`)

- `lib/music_studio/scheduling/notifier.ex` — `deliver_booking_emails/1` (single),
  `deliver_series_emails/1` (series), `deliver_reschedule/1` (exists), `ics_attrs/2`. The email
  `from` is already `{"Tristan Chalcraft Music", from_addr}`; the single CTA is "Add to Google
  Calendar"; the Google quick-add URL and details use `location: "Studio"`.
- `lib/music_studio/scheduling/ics.ex` — `ORGANIZER:mailto:#{a.organizer_email}` (no `CN`).
- `lib/music_studio/scheduling.ex` — `organizer_email` is sourced from `teacher.email`;
  `reschedule_booking/2` (~326) updates the lesson, updates the calendar event
  (`update_event`, nil-guarded), and is wired to re-notify.
- `lib/music_studio/scheduling/email_template.ex` — `html/1` + `text/1`, support a **single**
  `:cta` (`cta_block/1`).
- `lib/music_studio_web/live/booking_manage_live.ex` — cancel (single); skip/pause/cancel
  (series). No reschedule UI.
- `priv/repo/seeds.exs` — teacher seeded with `email: "tristan@example.com"` (the #11 leak).
- `config/config.exs` / `config/runtime.exs` — `MusicStudio.Scheduling` config
  (`notify_from`, `notify_to`, timezone, working hours).

## Design decisions (locked with the user)

1. **Single-source the studio identity in config**, decoupled from the teacher DB row. Add to
   `config :music_studio, MusicStudio.Scheduling`:
   - `studio_address: "14826 Thrift Avenue, White Rock, BC, Canada"`
   - `organizer_name: "Tristan Chalcraft Music"`
   - `organizer_email: "tchalcraftmusic@gmail.com"`
   These are non-secret defaults in `config.exs`; `runtime.exs` may override via env if wanted.
2. **Organizer** → the `.ics` emits `ORGANIZER;CN=Tristan Chalcraft Music:mailto:tchalcraftmusic@gmail.com`,
   the Google Calendar event uses the same, and the confirmation email sets **`Reply-To:
   tchalcraftmusic@gmail.com`** so RSVPs/replies reach Tristan. *Constraint:* the SMTP **From**
   stays a Resend-verified sender (display name "Tristan Chalcraft Music") — Resend cannot send
   *as* the Gmail address. The invite organizer reads **config**, not the teacher row — so the
   seeded teacher `tristan@example.com` no longer leaks into invites regardless. Also update the
   seed to the real address (`tchalcraftmusic@gmail.com`) so any residual `teacher.email` use is
   correct; grep for other `teacher.email` readers and confirm none reintroduce a placeholder.
3. **Location** everywhere (`studio_address`): email "Where" detail, ICS `LOCATION`, Google
   Calendar event location, and the Google quick-add URL — replacing `"Studio"`.
4. **Single vs. series** is explicit: the calendar event `SUMMARY` and the email title/subject
   distinguish them — single: `"Piano lesson"`; series: `"Piano lesson (weekly series)"`. The
   series confirmation ("… lessons are booked") already reads as plural; align the calendar
   `SUMMARY` and make the single email unmistakably a one-off.
5. **"Modify" button.** Extend `EmailTemplate` to support a **primary + secondary** CTA. Primary
   = **"Modify booking"** → `/book/manage/:token`. Secondary = "Add to Google Calendar" (the
   `.ics` attachment already covers adding). Applies to single and series confirmations.
6. **Reschedule UI — single lessons only** (series stays skip/pause/cancel; per-occurrence
   series reschedule is a deferred follow-up). On `/book/manage/:token` for a single lesson, add
   **"Pick a new time"**: reuse the `/book` availability grid to choose a new slot → call
   `Scheduling.reschedule_booking/2` → updates the DB lesson, updates the Google Calendar event
   (`update_event`, best-effort), and sends the existing `deliver_reschedule` email.

## Deliverables

### ① Config + identity
`studio_address`, `organizer_name`, `organizer_email` in scheduling config; seed teacher email
corrected; a small accessor (e.g. `Scheduling.studio_identity/0`) the notifier/ICS read from.

### ② `Notifier` + `ICS` + `EmailTemplate`
- ICS: `ORGANIZER;CN=…:mailto:…` from config; `LOCATION` = `studio_address`; `SUMMARY` reflects
  single/series.
- Notifier: `Reply-To` = `organizer_email`; email "Where" = `studio_address`; Google quick-add
  URL location = `studio_address`; single/series title; primary "Modify booking" CTA + secondary
  "Add to Google Calendar".
- EmailTemplate: two-CTA support (primary button + secondary link) in both `html/1` and `text/1`.

### ③ Reschedule UI (single lesson)
`BookingManageLive`: a "Pick a new time" path for single lessons reusing the availability grid,
calling `reschedule_booking/2`; success/flash + confirmation via `deliver_reschedule`.

## Testing

- Notifier unit tests: confirmation plaintext **contains the manage URL** (regression for #6);
  `Reply-To` = `organizer_email`; "Where" = the real address; single vs. series title.
- ICS tests: `ORGANIZER` carries `CN` + the Gmail `mailto`; `LOCATION` = the address; `SUMMARY`
  distinguishes single/series.
- Reschedule: LiveView test (select a new slot → success) + `reschedule_booking/2` test
  (lesson moved, calendar `update_event` invoked best-effort, `deliver_reschedule` sent).
- Full `mix precommit` green.

## Out of scope / deferred

- Per-occurrence **series** reschedule (single-lesson reschedule only for now).
- Any change to Resend domain verification / the SMTP From address value (tracked separately;
  From must already be a verified sender — this spec only adds Reply-To + display name).
- Recurring start/end dates (#16) — separate spec.
