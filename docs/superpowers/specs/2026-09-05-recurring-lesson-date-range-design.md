# Design: Recurring lesson start + end dates

Date: 2026-09-05
Status: approved (scope confirmed with the user)
Closes: #16 (start and end date for recurring lessons). Related: #7 (start-later upper bound)
is already fixed on `d4ed54f` — this builds on it.

## Context

A recurring series today starts on a chosen date and runs to a **fixed term end (June 30)** —
`Recurrence.term_end/1` computes the school-year-end June 30 from the start date, and
`Recurrence.occurrence_dates(start, interval_weeks, term_end)` walks weekly occurrences with
`Enum.take_while(&(Date.compare(&1, term_end) != :gt))`. The booking UI
(`lib/music_studio_web/live/booking_live.ex`) has a start-date stepper
(`start_earlier`/`start_later`, both now bounded) but **no end-date control** — every series
runs to June 30.

Tristan (#16): "Some people might not want to book the entire school year… provide a start and
end date. Options: **School year**, or **pick your date** (specify start + end)."

Decision (with the user): offer **"School year"** (now → Jun 30, default) vs **"Pick your
dates"** (custom start + end); the custom end is **capped at June 30** (keep the school-year
term model intact — smallest, safest change).

All work ships on branch **`recurring-date-range`** (its own `wt` worktree). App changes only;
PR to `music_studio`, CI green, batched for the next manual deploy. A migration is likely (an
enrollment end-date column) — must run cleanly on Render boot (`bin/migrate`).

## Relevant code (verified on deployed `d4ed54f`)

- `lib/music_studio/scheduling/recurrence.ex` — `term_end/1` (Jun 30 of the school year),
  `occurrence_dates/3` (takes the term end as an argument → the natural seam: pass
  `min(custom_end, term_end)`).
- `lib/music_studio_web/live/booking_live.ex` — recurring path: `series_start`, `rec_pattern`,
  `series_preview`, `preview_series`, `can_start_earlier?/2`, `can_start_later?/2`; renders
  "N lessons through Jun 30".
- `lib/music_studio/scheduling.ex` — `preview_series`, `create_series` (inserts the
  `Enrollment` + lessons).
- `lib/music_studio/scheduling/enrollment.ex` — enrollment schema (confirm whether it stores a
  series end; add an `ends_on :date` if not).

## Design

1. **UI (`BookingLive`, recurring path).** Add a mode toggle:
   - **School year** (default): behaves exactly as today (start → Jun 30).
   - **Pick your dates**: reveals a start picker (the existing stepper is fine) **and an end
     picker**. End is bounded: `min = series_start + one interval`, `max = term_end` (Jun 30).
     Disable Continue when the resulting bookable set is empty (consistent with the #7 fix).
   - Preview line reads e.g. "8 lessons, Sep 15 → Dec 19".
2. **Preview/creation.** `preview_series`/`create_series` accept an optional `ends_on` and pass
   `min(ends_on, term_end)` into `Recurrence.occurrence_dates/3`. When absent (School year),
   behavior is unchanged (`term_end`).
3. **Persistence.** The `Enrollment` records the chosen end (`ends_on :date`, defaulting to
   `term_end` for School-year series) so `held_intervals`/management reflect the real horizon.
   Add a migration if the column doesn't exist. (Confirm the schema first; the seam is small.)

## Testing

- `Recurrence`/`preview_series`: a custom end yields the correct occurrence **count** and last
  date; end **cannot exceed** June 30 (values past it clamp to term end); end **≥ start + one
  interval**; School-year mode is unchanged (regression).
- `create_series`: persists `ends_on`; `held_intervals` reflect it (no over-holding past the
  chosen end).
- LiveView test: choosing "Pick your dates" reveals the end picker; the preview count updates;
  Continue disables on an empty set.
- Migration (if added) runs clean; full `mix precommit` green.

## Out of scope / deferred

- Ends **past** the school year (into summer / next term) — capped at Jun 30 for now;
  revisit if Tristan wants year-round enrollment.
- Named **preset terms** (Fall/Spring) — not now; "School year" + "Pick your dates" only.
- Email/invite content (#15/#11) — separate spec; the recurring email already reads as a series.
