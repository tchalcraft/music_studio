# Booking email + calendar invite + single-lesson reschedule — Implementation Plan

> **For agentic workers:** implements `docs/superpowers/specs/2026-09-05-booking-email-and-reschedule-design.md` (#15, #11; regression test for #6). Executed inline TDD.

**Goal:** Fix the booking confirmation email + calendar invite (organizer, location, single/series, Modify button) and add a single-lesson reschedule UI.

**Architecture:** Single-source the studio identity in scheduling config (`studio_address`, `organizer_name`, `organizer_email`) exposed via `Scheduling.studio_identity/0`; Notifier/ICS/calendar writes read it instead of the teacher DB row. Extend `EmailTemplate` for a secondary CTA. Add a "Pick a new time" flow to `BookingManageLive` for single lessons, reusing `Scheduling.list_available_slots/1` and the existing `reschedule_booking/2`.

**Tech Stack:** Elixir 1.18 / Phoenix 1.7 / LiveView 1.2, Swoosh, ExUnit.

## Global Constraints
- Phoenix pinned 1.7; no new deps. No migrations.
- `mix precommit` green (run as `MIX_TEST_PARTITION=_email mix precommit`).
- Best-effort side effects (calendar/email) must never fail the core action.
- Single-lesson reschedule ONLY; series stays skip/pause/cancel.

---

### Task 1: Studio identity in config + `studio_identity/0`
**Files:** Modify `config/config.exs` (scheduling block), `lib/music_studio/scheduling.ex`, `priv/repo/seeds.exs`; Test `test/music_studio/scheduling/config_test.exs` (or a new identity test).
- Add `studio_address`, `organizer_name`, `organizer_email` to `config :music_studio, MusicStudio.Scheduling`.
- Add `Scheduling.studio_identity/0 :: %{name, email, address}`.
- Seed teacher email → `tchalcraftmusic@gmail.com`.
- Point `email_details/5` + `lesson_email_details/1` organizer at `studio_identity/0`.

### Task 2: ICS + calendar writes use identity/location + single-series SUMMARY
**Files:** `lib/music_studio/scheduling/notifier.ex` (`ics_attrs`), `lib/music_studio/scheduling.ex` (`write_event`, `update_event`, `add_series_event`); Test `test/music_studio/scheduling/ics_test.exs`.
- `.ics` LOCATION = address; SUMMARY = `"Piano lesson"` (single; the .ics is single-only).
- Calendar event SUMMARY gets a `(weekly series)` suffix for series lessons; LOCATION = address everywhere.

### Task 3: Notifier — location, Reply-To, Modify button
**Files:** `lib/music_studio/scheduling/notifier.ex`, `lib/music_studio/scheduling/email_template.ex`; Test `test/music_studio/scheduling/notifier_test.exs`, `email_template_test.exs`.
- Email "Where" + Google quick-add URL location = address.
- `Reply-To` = organizer email on all visitor emails.
- `EmailTemplate` gains an optional `:cta_secondary`; single booking email: primary "Modify booking" (manage_url) + secondary "Add to Google Calendar" (gcal).
- Regression: plaintext confirmation contains the manage URL (#6).

### Task 4: Reschedule UI (single lesson) in BookingManageLive
**Files:** `lib/music_studio_web/live/booking_manage_live.ex`; Test `test/music_studio_web/live/booking_manage_live_test.exs`.
- "Pick a new time" reveals available slots (via `list_available_slots/1` for the lesson's instrument+duration), student picks → `reschedule_booking/2` → success state.

### Task 5: precommit + PR
- `MIX_TEST_PARTITION=_email mix precommit` green; push; open PR (#15/#11; notes #6 regression).
