# Track B — Recurring School-Year Lessons — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a visitor book a weekly or bi-weekly lesson series for the school year in one action; hold their time slot across skips and month-long pauses; and offer alternates for weeks that can't be booked.

**Architecture:** Reuse `Teaching.Enrollment` as the series parent (add recurrence columns); each occurrence is a `Teaching.Lesson` carrying `enrollment_id`. A new pure `MusicStudio.Scheduling.Recurrence` module does all date math (term end, occurrence projection, DST-correct local→UTC). `MusicStudio.Scheduling` gains `held_intervals/2` (so a series' recurring time is subtracted from availability even on skipped weeks — **no change to the pure `Availability.compute/1`**), plus `preview_series/1`, `create_series/1`, and skip/pause/cancel functions. The DB exclusion constraint keeps guarding actually-scheduled lessons.

**Tech Stack:** Elixir 1.18 / Phoenix 1.7 / LiveView 1.2, Ecto + Postgres, `Req` (Google, stubbed in tests), `tzdata`, UUIDv7.

**Plan doc for the umbrella design:** `~/.claude/plans/i-want-to-change-goofy-honey.md`. **Depends on:** Track A (stepped `BookingLive`) for the Schedule-step UI, and Track C (`Scheduling.Notifier` HTML template) for the series email — build B after A and C. If a dependency isn't present when a UI/email task is reached, wire the minimal version and leave a `# TODO(track-a/c)` note; the context/tests below don't depend on A or C.

## Global Constraints

- Work in the **`music_studio.scheduling`** worktree; all paths relative to it. Repo is **jj colocated with git** — `git commit` works. End commit bodies with the repo's trailer convention.
- **`mix precommit` must stay green**: `compile --warnings-as-errors --force`, `skills.check`, `deps.unlock --unused`, `format`, `gettext.extract --check-up-to-date`, `credo --strict`, `sobelow`, `test`. Two credo rules bite here: **max nesting depth 2**, and **alphabetical alias ordering** (`alias MusicStudio.{Analytics, Catalog, Repo, Teaching}` before `alias MusicStudio.Scheduling.{...}` before `alias MusicStudio.Teaching.Lesson`).
- **Phoenix `~> 1.7.0`, LiveView `~> 1.2`** — no 1.8-only APIs.
- New columns follow **`MusicStudio.Schema`** conventions: `:utc_datetime_usec` timestamps, `deleted_at` soft-delete, `Ecto.Enum` as strings. Enrollment already uses `use MusicStudio.Schema` (UUIDv7 keys).
- **Timezone `America/Vancouver`**; interval is 1 or 2 weeks; grid 30 min, buffer 15 min, min-notice 24 h — all under `config :music_studio, MusicStudio.Scheduling`.
- **Tests** use local Postgres (`config/test.exs`); Google HTTP is stubbed with `Req.Test` via the `:scheduling_req_options` seam (`plug: {Req.Test, MusicStudio.Scheduling.GoogleAuth}`). No live external calls.
- **Slot times are stored as `:utc_datetime`** (tz-less UTC in PG); the recurring time is a **local wall-clock** `:time` + `recurrence_timezone`, converted to UTC per occurrence (DST-safe).

## Existing code this builds on (verified)

- `lib/music_studio/scheduling.ex` — `create_booking/1`, `after_booking/5`, `booked_intervals/2` (returns `[%{starts_at, ends_at}]` for scheduled, non-deleted lessons overlapping the window), `list_available_slots/1`, and helpers `upsert_student/1`, `fetch_teacher/0`, `fetch_instrument/1`, `fetch_offering/1`, `gen_token/0`, `side_effect/1`, `target_calendar/0`, `cfg/1`, `get_lesson_by_token/1`, `write_event/4`, `email_details/5`.
- `lib/music_studio/scheduling/availability.ex` — `compute/1` takes `%{blocks, booked, duration_minutes, grid_minutes, buffer_minutes, min_notice_minutes, now}` → `[%Slot{starts_at, ends_at}]` (UTC). Pure. **Do not modify.**
- `lib/music_studio/teaching/enrollment.ex` — `@statuses [:active, :paused, :completed, :cancelled]`, `started_on`/`ended_on`/`deleted_at`, FKs student/teacher/instrument/offering/location.
- `lib/music_studio/teaching/lesson.ex` — `enrollment_id` (optional FK), `status`, `scheduled_start/end`, `price_cents`/`currency`, `google_event_id`, `booking_token` (unique), exclusion constraint `lessons_no_overlap` + `exclusion_constraint(:scheduled_start, name: "lessons_no_overlap", message: "is already booked")` in the changeset.
- `lib/music_studio/teaching.ex` — `create_student/1`, `get_student_by_email/1`, `create_enrollment/1`.
- Migration convention: `priv/repo/migrations/YYYYMMDDHHMMSS_*.exs`; see `20260901120000_add_scheduling.exs` for the `up/0`+`down/0` style.

---

## B1 — Book a series

### Task 1: Recurrence columns on `enrollments`

**Files:**
- Create: `priv/repo/migrations/20260902130000_add_recurring_enrollments.exs`
- Modify: `lib/music_studio/teaching/enrollment.ex`
- Test: `test/music_studio/teaching/enrollment_recurrence_test.exs`

**Interfaces:**
- Produces: `enrollments` gains `recurrence_interval_weeks :integer`, `recurrence_weekday :integer`, `recurrence_time :time`, `recurrence_timezone :string`, `booking_token :string` (unique), `contact_email :string` (all nullable). `Enrollment.changeset/2` casts them; `booking_token` unique-constrained.

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/teaching/enrollment_recurrence_test.exs
defmodule MusicStudio.Teaching.EnrollmentRecurrenceTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Catalog
  alias MusicStudio.Repo
  alias MusicStudio.Teaching
  alias MusicStudio.Teaching.Enrollment

  test "an enrollment stores a recurrence schedule + series token" do
    {:ok, teacher} = Catalog.create_teacher(%{name: "T", active: true})
    {:ok, piano} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, student} = Teaching.create_student(%{first_name: "S", status: "prospective"})

    attrs = %{
      status: :active,
      started_on: ~D[2026-09-08],
      ended_on: ~D[2027-06-30],
      recurrence_interval_weeks: 1,
      recurrence_weekday: 2,
      recurrence_time: ~T[16:00:00],
      recurrence_timezone: "America/Vancouver",
      booking_token: "series-tok-1",
      contact_email: "sam@example.com",
      teacher_id: teacher.id,
      student_id: student.id,
      instrument_id: piano.id
    }

    assert {:ok, e} = %Enrollment{} |> Enrollment.changeset(attrs) |> Repo.insert()
    assert e.recurrence_interval_weeks == 1
    assert e.recurrence_time == ~T[16:00:00]
    assert e.booking_token == "series-tok-1"

    {:error, cs} =
      %Enrollment{} |> Enrollment.changeset(%{attrs | student_id: student.id}) |> Repo.insert()

    assert "has already been taken" in errors_on(cs).booking_token
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/teaching/enrollment_recurrence_test.exs`
Expected: FAIL — unknown fields / no migration.

- [ ] **Step 3: Write the migration**

```elixir
# priv/repo/migrations/20260902130000_add_recurring_enrollments.exs
defmodule MusicStudio.Repo.Migrations.AddRecurringEnrollments do
  use Ecto.Migration

  def change do
    alter table(:enrollments) do
      add :recurrence_interval_weeks, :integer
      add :recurrence_weekday, :integer
      add :recurrence_time, :time
      add :recurrence_timezone, :string
      add :booking_token, :string
      add :contact_email, :string
    end

    create unique_index(:enrollments, [:booking_token])
  end
end
```

- [ ] **Step 4: Update the Enrollment schema + changeset**

In `lib/music_studio/teaching/enrollment.ex`, add fields inside `schema "enrollments" do` (after `field :deleted_at, :utc_datetime_usec`):

```elixir
    field :recurrence_interval_weeks, :integer
    field :recurrence_weekday, :integer
    field :recurrence_time, :time
    field :recurrence_timezone, :string
    field :booking_token, :string
    field :contact_email, :string
```

Add those six atoms to the `cast/3` list, and after `validate_required(...)` add:

```elixir
    |> validate_inclusion(:recurrence_interval_weeks, [1, 2])
    |> validate_inclusion(:recurrence_weekday, 1..7)
    |> unique_constraint(:booking_token)
```

- [ ] **Step 5: Migrate and run the test**

Run: `mix ecto.migrate && mix test test/music_studio/teaching/enrollment_recurrence_test.exs`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/20260902130000_add_recurring_enrollments.exs lib/music_studio/teaching/enrollment.ex test/music_studio/teaching/enrollment_recurrence_test.exs
git commit -m "Add recurrence columns + series token to enrollments"
```

---

### Task 2: `Scheduling.Recurrence` — pure date math (term end, projection, DST)

**Files:**
- Create: `lib/music_studio/scheduling/recurrence.ex`
- Test: `test/music_studio/scheduling/recurrence_test.exs`

**Interfaces:**
- Produces: `Recurrence.term_end(Date.t()) :: Date.t()` — next June 30 on/after the date.
- Produces: `Recurrence.occurrence_dates(start :: Date.t(), interval_weeks :: 1|2, term_end :: Date.t()) :: [Date.t()]`.
- Produces: `Recurrence.occurrence_utc(Date.t(), Time.t(), tz :: String.t()) :: DateTime.t()` — the occurrence start in UTC, DST-safe.

- [ ] **Step 1: Write the failing tests**

```elixir
# test/music_studio/scheduling/recurrence_test.exs
defmodule MusicStudio.Scheduling.RecurrenceTest do
  use ExUnit.Case, async: true

  alias MusicStudio.Scheduling.Recurrence

  test "term_end is the next June 30 on/after the start date" do
    assert Recurrence.term_end(~D[2026-09-08]) == ~D[2027-06-30]
    assert Recurrence.term_end(~D[2027-01-05]) == ~D[2027-06-30]
    assert Recurrence.term_end(~D[2027-06-30]) == ~D[2027-06-30]
    assert Recurrence.term_end(~D[2027-07-01]) == ~D[2028-06-30]
  end

  test "weekly occurrences step 7 days and stop at term end" do
    dates = Recurrence.occurrence_dates(~D[2027-06-16], 1, ~D[2027-06-30])
    assert dates == [~D[2027-06-16], ~D[2027-06-23], ~D[2027-06-30]]
  end

  test "bi-weekly occurrences step 14 days" do
    dates = Recurrence.occurrence_dates(~D[2027-06-02], 2, ~D[2027-06-30])
    assert dates == [~D[2027-06-02], ~D[2027-06-16], ~D[2027-06-30]]
  end

  test "occurrence_utc keeps 16:00 local across a DST change (PDT -> PST)" do
    # Pacific leaves DST 2026-11-01; 16:00 local is 23:00Z in Oct, 00:00Z next day in Nov.
    oct = Recurrence.occurrence_utc(~D[2026-10-27], ~T[16:00:00], "America/Vancouver")
    nov = Recurrence.occurrence_utc(~D[2026-11-03], ~T[16:00:00], "America/Vancouver")
    assert DateTime.to_iso8601(oct) == "2026-10-27T23:00:00Z"
    assert DateTime.to_iso8601(nov) == "2026-11-04T00:00:00Z"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/music_studio/scheduling/recurrence_test.exs`
Expected: FAIL — `Recurrence` undefined.

- [ ] **Step 3: Implement `Recurrence`**

```elixir
# lib/music_studio/scheduling/recurrence.ex
defmodule MusicStudio.Scheduling.Recurrence do
  @moduledoc """
  Pure date math for recurring lesson series: the school-year term boundary, the list of
  occurrence dates for a weekly/bi-weekly cadence, and the DST-safe conversion of a local
  wall-clock time on a given date to a UTC `DateTime`. No I/O — fully unit-testable.
  """

  @spec term_end(Date.t()) :: Date.t()
  def term_end(%Date{year: year} = date) do
    june30 = Date.new!(year, 6, 30)
    if Date.compare(date, june30) in [:lt, :eq], do: june30, else: Date.new!(year + 1, 6, 30)
  end

  @spec occurrence_dates(Date.t(), 1 | 2, Date.t()) :: [Date.t()]
  def occurrence_dates(start_date, interval_weeks, term_end) do
    start_date
    |> Stream.iterate(&Date.add(&1, interval_weeks * 7))
    |> Enum.take_while(&(Date.compare(&1, term_end) != :gt))
  end

  @spec occurrence_utc(Date.t(), Time.t(), String.t()) :: DateTime.t()
  def occurrence_utc(date, %Time{} = time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _just_before, just_after} -> DateTime.shift_zone!(just_after, "Etc/UTC")
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/music_studio/scheduling/recurrence_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling/recurrence.ex test/music_studio/scheduling/recurrence_test.exs
git commit -m "Add pure Scheduling.Recurrence date math (term end, projection, DST)"
```

---

### Task 3: Slot-holding — `held_intervals/2` merged into availability

**Files:**
- Modify: `lib/music_studio/scheduling.ex` (add `held_intervals/2`; merge into the `booked` list used by `list_available_slots/1`)
- Test: `test/music_studio/scheduling/held_slots_test.exs`

**Interfaces:**
- Produces: `Scheduling.held_intervals(time_min :: DateTime.t(), time_max :: DateTime.t()) :: [%{starts_at: DateTime.t(), ends_at: DateTime.t()}]` — recurring occurrences of **active or paused** enrollments (recurrence set, not deleted) projected into the window, using the enrollment's offering duration.
- Change: `list_available_slots/1` passes `booked: booked_intervals(...) ++ held_intervals(...)` to `Availability.compute/1`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/scheduling/held_slots_test.exs
defmodule MusicStudio.Scheduling.HeldSlotsTest do
  use MusicStudio.DataCase, async: false

  alias MusicStudio.{Catalog, Repo, Teaching}
  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}
  alias MusicStudio.Teaching.Enrollment

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, teacher} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, piano} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, off} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})
    {:ok, student} = Teaching.create_student(%{first_name: "S", status: "prospective"})

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google", refresh_token: "rt", access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c", target_calendar_id: "c"
      })

    # A paused series: Tuesdays 16:00 PT, holding the slot for the whole term.
    {:ok, _enr} =
      %Enrollment{}
      |> Enrollment.changeset(%{
        status: :paused,
        started_on: ~D[2026-09-08],
        ended_on: ~D[2027-06-30],
        recurrence_interval_weeks: 1,
        recurrence_weekday: 2,
        recurrence_time: ~T[16:00:00],
        recurrence_timezone: "America/Vancouver",
        booking_token: "series-1",
        contact_email: "held@example.com",
        teacher_id: teacher.id, student_id: student.id, instrument_id: piano.id, offering_id: off.id
      })
      |> Repo.insert()

    %{}
  end

  test "a paused series' recurring time is withheld from availability" do
    # Availability calendar wide open on Tue Sep 15 2026, 15:00-18:00 PT.
    Req.Test.stub(GoogleAuth, fn conn ->
      Req.Test.json(conn, %{
        "items" => [%{
          "start" => %{"dateTime" => "2026-09-15T15:00:00-07:00"},
          "end" => %{"dateTime" => "2026-09-15T18:00:00-07:00"}
        }]
      })
    end)

    {:ok, slots} =
      Scheduling.list_available_slots(%{
        instrument_slug: "piano", duration_minutes: 60,
        from: ~D[2026-09-15], to: ~D[2026-09-15]
      })

    starts = Enum.map(slots, &(&1.starts_at |> DateTime.shift_zone!("America/Vancouver") |> Calendar.strftime("%-I:%M %p")))
    # 16:00 held (buffer 15m also blocks 15:30 and 16:30); 15:00 and 17:00 remain.
    refute "4:00 PM" in starts
    refute "3:30 PM" in starts
    refute "4:30 PM" in starts
    assert "3:00 PM" in starts
    assert "5:00 PM" in starts
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/held_slots_test.exs`
Expected: FAIL — `4:00 PM` still offered (held_intervals not applied).

- [ ] **Step 3: Implement `held_intervals/2` and merge it**

In `lib/music_studio/scheduling.ex`, add `Enrollment` to the Teaching alias usage by adding an alias near the top (keep alphabetical among the `MusicStudio.Teaching.*` group):

```elixir
  alias MusicStudio.Teaching.Enrollment
  alias MusicStudio.Teaching.Lesson
```

(and add `Recurrence` to the Scheduling alias group:)

```elixir
  alias MusicStudio.Scheduling.{Availability, Credentials, GoogleCalendar, Notifier, Recurrence}
```

In `list_available_slots/1`, change the `booked:` line:

```elixir
          booked: booked_intervals(time_min, time_max) ++ held_intervals(time_min, time_max),
```

Add the function (near `booked_intervals/2`):

```elixir
  # Recurring slots of active/paused series, projected into the window. These stay reserved
  # even on skipped/paused weeks (no scheduled Lesson row), so the student keeps their time.
  defp held_intervals(time_min, time_max) do
    Enrollment
    |> where([e], e.status in [:active, :paused] and is_nil(e.deleted_at))
    |> where([e], not is_nil(e.recurrence_weekday) and not is_nil(e.recurrence_time))
    |> preload(:offering)
    |> Repo.all()
    |> Enum.flat_map(&series_intervals(&1, time_min, time_max))
  end

  defp series_intervals(enrollment, time_min, time_max) do
    duration = enrollment.offering && enrollment.offering.duration_minutes

    if is_nil(duration) do
      []
    else
      term_end = Recurrence.term_end(enrollment.started_on)

      enrollment.started_on
      |> Recurrence.occurrence_dates(enrollment.recurrence_interval_weeks, term_end)
      |> Enum.map(fn date ->
        starts = Recurrence.occurrence_utc(date, enrollment.recurrence_time, enrollment.recurrence_timezone)
        %{starts_at: starts, ends_at: DateTime.add(starts, duration, :minute)}
      end)
      |> Enum.filter(fn %{starts_at: s, ends_at: e} ->
        DateTime.compare(s, time_max) == :lt and DateTime.compare(e, time_min) == :gt
      end)
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/held_slots_test.exs`
Expected: PASS (1 test). Also run `mix test test/music_studio/scheduling_test.exs` to confirm the single-booking flow is unaffected.

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling.ex test/music_studio/scheduling/held_slots_test.exs
git commit -m "Hold recurring series slots in availability via held_intervals"
```

---

### Task 4: `preview_series/1` — classify each week bookable vs conflicted

**Files:**
- Modify: `lib/music_studio/scheduling.ex`
- Test: `test/music_studio/scheduling/preview_series_test.exs`

**Interfaces:**
- Produces: `Scheduling.preview_series(%{instrument_slug, duration_minutes, first_starts_at: DateTime, interval_weeks: 1|2}) :: {:ok, %{start_date: Date, interval_weeks, term_end: Date, bookable: [DateTime], conflicted: [DateTime]}} | {:error, term()}`. `bookable`/`conflicted` are occurrence start `DateTime`s (UTC). A week is **bookable** if its recurring time is a slot returned by `Availability.compute/1` for that day (inside an availability block, clear of booked+held+buffer, past min-notice).

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/scheduling/preview_series_test.exs
defmodule MusicStudio.Scheduling.PreviewSeriesTest do
  use MusicStudio.DataCase, async: false

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google", refresh_token: "rt", access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c", target_calendar_id: "c"
      })

    :ok
  end

  test "projects weekly occurrences to June 30 and marks the open ones bookable" do
    # Availability calendar: every day it queries, return a 15:00-18:00 PT block for THAT day.
    Req.Test.stub(GoogleAuth, fn conn ->
      # Echo a block for whatever timeMin day was requested.
      day = conn.query_params["timeMin"] |> String.slice(0, 10)
      Req.Test.json(conn, %{
        "items" => [%{
          "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
          "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
        }]
      })
    end)

    first = MusicStudio.Scheduling.Recurrence.occurrence_utc(~D[2026-09-08], ~T[16:00:00], "America/Vancouver")

    {:ok, preview} =
      Scheduling.preview_series(%{
        instrument_slug: "piano", duration_minutes: 60,
        first_starts_at: first, interval_weeks: 1
      })

    assert preview.term_end == ~D[2027-06-30]
    assert preview.start_date == ~D[2026-09-08]
    # Every Tuesday Sep 8 2026 -> Jun 29 2027 is open in this stub.
    assert length(preview.bookable) >= 40
    assert preview.conflicted == []
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/preview_series_test.exs`
Expected: FAIL — `preview_series/1` undefined.

- [ ] **Step 3: Implement `preview_series/1`**

Add to `lib/music_studio/scheduling.ex` (public, near `list_available_slots/1`):

```elixir
  @spec preview_series(map()) :: {:ok, map()} | {:error, term()}
  def preview_series(%{
        instrument_slug: slug,
        duration_minutes: duration,
        first_starts_at: first_starts_at,
        interval_weeks: interval_weeks
      }) do
    tz = cfg(:studio_timezone)
    local_first = DateTime.shift_zone!(first_starts_at, tz)
    start_date = DateTime.to_date(local_first)
    time = DateTime.to_time(local_first) |> Time.truncate(:second)
    term_end = Recurrence.term_end(start_date)
    dates = Recurrence.occurrence_dates(start_date, interval_weeks, term_end)

    {bookable, conflicted} =
      Enum.split_with(dates, fn date ->
        starts = Recurrence.occurrence_utc(date, time, tz)
        slot_bookable?(slug, duration, date, starts)
      end)
      |> then(fn {b, c} ->
        {Enum.map(b, &Recurrence.occurrence_utc(&1, time, tz)),
         Enum.map(c, &Recurrence.occurrence_utc(&1, time, tz))}
      end)

    {:ok,
     %{
       start_date: start_date,
       interval_weeks: interval_weeks,
       term_end: term_end,
       bookable: bookable,
       conflicted: conflicted
     }}
  end

  # True if `starts` is one of the slots availability offers for that single day.
  defp slot_bookable?(slug, duration, date, starts) do
    case list_available_slots(%{instrument_slug: slug, duration_minutes: duration, from: date, to: date}) do
      {:ok, slots} -> Enum.any?(slots, &(DateTime.compare(&1.starts_at, starts) == :eq))
      {:error, _} -> false
    end
  end
```

Note: `slot_bookable?/4` issues one Google fetch per occurrence day (≤~40). Acceptable for a booking-time preview; if it becomes slow, a later optimization can fetch the whole term once and reuse `Availability.compute/1` per day in memory (documented as a follow-up, not built now).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/preview_series_test.exs`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling.ex test/music_studio/scheduling/preview_series_test.exs
git commit -m "Add Scheduling.preview_series classification across the term"
```

---

### Task 5: `create_series/1` — enrollment + lessons + side effects

**Files:**
- Modify: `lib/music_studio/scheduling.ex`
- Test: `test/music_studio/scheduling/create_series_test.exs`

**Interfaces:**
- Produces: `Scheduling.create_series(%{instrument_slug, duration_minutes, first_starts_at: DateTime, interval_weeks: 1|2, name, email, phone}) :: {:ok, %{enrollment: Enrollment.t(), lessons: [Lesson.t()], conflicted: [DateTime]}} | {:error, term()}`. One transaction: upsert student → insert enrollment (recurrence fields, `started_on`, `ended_on` = term_end, series `booking_token`, `contact_email`) → insert a Lesson per bookable occurrence (shared `enrollment_id`, per-lesson `booking_token`). Post-commit: one Google event per lesson, one series email, an Analytics `series_booked` event.

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/scheduling/create_series_test.exs
defmodule MusicStudio.Scheduling.CreateSeriesTest do
  use MusicStudio.DataCase, async: false
  import Swoosh.TestAssertions

  alias MusicStudio.{Repo, Teaching}
  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}
  alias MusicStudio.Teaching.Lesson

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google", refresh_token: "rt", access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c", target_calendar_id: "c"
      })

    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          day = conn.query_params["timeMin"] |> String.slice(0, 10)
          Req.Test.json(conn, %{"items" => [%{
            "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
            "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
          }]})

        _ -> Req.Test.json(conn, %{"id" => "evt-#{System.unique_integer([:positive])}"})
      end
    end)

    :ok
  end

  test "books a weekly series: one enrollment, a lesson per week, one email" do
    first = Scheduling.Recurrence.occurrence_utc(~D[2027-06-08], ~T[16:00:00], "America/Vancouver")

    {:ok, %{enrollment: enr, lessons: lessons}} =
      Scheduling.create_series(%{
        instrument_slug: "piano", duration_minutes: 60,
        first_starts_at: first, interval_weeks: 1,
        name: "Sam Lee", email: "sam@example.com", phone: "604"
      })

    # Jun 8, 15, 22, 29 2027 -> 4 weeks (term end Jun 30).
    assert length(lessons) == 4
    assert enr.status == :active
    assert enr.ended_on == ~D[2027-06-30]
    assert enr.booking_token
    assert Enum.all?(lessons, &(&1.enrollment_id == enr.id))
    assert Repo.aggregate(from(l in Lesson, where: l.enrollment_id == ^enr.id), :count) == 4
    assert_email_sent(fn e -> e.subject =~ "lessons" or e.subject =~ "series" end)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/create_series_test.exs`
Expected: FAIL — `create_series/1` undefined.

- [ ] **Step 3: Implement `create_series/1` + helpers**

Add to `lib/music_studio/scheduling.ex`:

```elixir
  @spec create_series(map()) :: {:ok, map()} | {:error, term()}
  def create_series(params) do
    with {:ok, teacher} <- fetch_teacher(),
         {:ok, instrument} <- fetch_instrument(params.instrument_slug),
         {:ok, offering} <- fetch_offering(params.duration_minutes),
         {:ok, preview} <- preview_series(params) do
      tz = cfg(:studio_timezone)
      local_first = DateTime.shift_zone!(params.first_starts_at, tz)

      series = %{
        teacher: teacher,
        instrument: instrument,
        offering: offering,
        preview: preview,
        weekday: Date.day_of_week(DateTime.to_date(local_first)),
        time: local_first |> DateTime.to_time() |> Time.truncate(:second),
        tz: tz
      }

      case Repo.transaction(series_multi(params, series)) do
        {:ok, %{enrollment: enr} = changes} ->
          lessons = collect_lessons(changes)
          after_series(enr, lessons, series, params)
          {:ok, %{enrollment: enr, lessons: lessons, conflicted: preview.conflicted}}

        {:error, _step, %Ecto.Changeset{errors: errors}, _} ->
          booking_error(errors)

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp series_multi(params, series) do
    base =
      Multi.new()
      |> Multi.run(:student, fn _repo, _ -> upsert_student(params) end)
      |> Multi.insert(:enrollment, fn %{student: student} ->
        Teaching.change_enrollment(%Teaching.Enrollment{}, %{
          status: :active,
          started_on: series.preview.start_date,
          ended_on: series.preview.term_end,
          recurrence_interval_weeks: series.preview.interval_weeks,
          recurrence_weekday: series.weekday,
          recurrence_time: series.time,
          recurrence_timezone: series.tz,
          booking_token: gen_token(),
          contact_email: params.email,
          teacher_id: series.teacher.id,
          student_id: student.id,
          instrument_id: series.instrument.id,
          offering_id: series.offering.id
        })
      end)

    series.preview.bookable
    |> Enum.with_index()
    |> Enum.reduce(base, fn {starts_at, i}, multi ->
      Multi.insert(multi, {:lesson, i}, fn %{student: student, enrollment: enrollment} ->
        ends_at = DateTime.add(starts_at, params.duration_minutes, :minute)

        Lesson.changeset(%Lesson{}, %{
          scheduled_start: DateTime.truncate(starts_at, :second),
          scheduled_end: DateTime.truncate(ends_at, :second),
          duration_minutes: params.duration_minutes,
          status: :scheduled,
          price_cents: series.offering.price_cents,
          currency: series.offering.currency,
          teacher_id: series.teacher.id,
          student_id: student.id,
          instrument_id: series.instrument.id,
          offering_id: series.offering.id,
          enrollment_id: enrollment.id,
          booking_token: gen_token()
        })
      end)
    end)
  end

  defp collect_lessons(changes) do
    changes
    |> Enum.filter(fn {k, _v} -> match?({:lesson, _}, k) end)
    |> Enum.sort_by(fn {{:lesson, i}, _v} -> i end)
    |> Enum.map(fn {_k, lesson} -> lesson end)
  end

  defp after_series(enrollment, lessons, series, params) do
    Enum.each(lessons, fn lesson ->
      side_effect(fn ->
        ends_at = DateTime.add(lesson.scheduled_start, lesson.duration_minutes, :minute)
        write_event(lesson, series.instrument, params, ends_at)
      end)
    end)

    side_effect(fn -> Notifier.deliver_series_emails(series_email_details(enrollment, lessons, series, params)) end)

    side_effect(fn ->
      Analytics.record_event(%{
        verb: "series_booked",
        subject_type: "enrollment",
        subject_id: enrollment.id,
        metadata: %{
          "instrument" => params.instrument_slug,
          "interval_weeks" => series.preview.interval_weeks,
          "lessons" => length(lessons),
          "conflicted" => length(series.preview.conflicted)
        }
      })
    end)

    :ok
  end

  defp series_email_details(enrollment, lessons, series, params) do
    %{
      visitor_name: params.name,
      visitor_email: params.email,
      instrument: String.downcase(series.instrument.name),
      interval_weeks: series.preview.interval_weeks,
      lesson_starts: Enum.map(lessons, & &1.scheduled_start),
      conflicted: series.preview.conflicted,
      manage_url: MusicStudioWeb.Endpoint.url() <> "/book/manage/" <> enrollment.booking_token,
      timezone: series.tz
    }
  end
```

Note: `write_event/4` and `email_details/5` already exist. `Notifier.deliver_series_emails/1` is added in Track C; if Track C is not yet built, add a temporary text-only `deliver_series_emails/1` to `Scheduling.Notifier` that lists the lesson dates, and mark it `# TODO(track-c): HTML template`.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/create_series_test.exs`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling.ex test/music_studio/scheduling/create_series_test.exs
git commit -m "Add Scheduling.create_series (enrollment + weekly lessons + side effects)"
```

---

### Task 6: `BookingLive` — recurring option in the Schedule step

**Files:**
- Modify: `lib/music_studio_web/live/booking_live.ex`
- Test: `test/music_studio_web/live/booking_live_recurring_test.exs`

**Interfaces:**
- Consumes: `Scheduling.preview_series/1`, `Scheduling.create_series/1`.
- Produces: on the Schedule step (Track A), a "Just once / Weekly / Every other week" choice; choosing recurring picks the first time via existing slot buttons, shows a preview (N lessons through June, M weeks need another time), and the Confirm action calls `create_series/1`.

- [ ] **Step 1: Write the failing test** (drives the LiveView end to end with Google stubbed)

```elixir
# test/music_studio_web/live/booking_live_recurring_test.exs
defmodule MusicStudioWeb.BookingLiveRecurringTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google", refresh_token: "rt", access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c", target_calendar_id: "c"
      })

    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          day = conn.query_params["timeMin"] |> String.slice(0, 10)
          Req.Test.json(conn, %{"items" => [%{
            "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
            "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
          }]})

        _ -> Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)

    :ok
  end

  test "choosing weekly + a slot shows a series preview", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")

    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_change(view, "set_cadence", %{"cadence" => "weekly"})

    # pick the first available slot
    html = render(view)
    assert html =~ "Available times"
    # (the test picks a slot start from the rendered buttons; exact selector per Track A markup)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio_web/live/booking_live_recurring_test.exs`
Expected: FAIL — no `set_cadence` handler / no preview.

- [ ] **Step 3: Implement the LiveView changes**

Add assigns in `mount/3`: `:cadence` (`"once" | "weekly" | "biweekly"`, default `"once"`), `:series_preview` (nil). Add a `handle_event("set_cadence", %{"cadence" => c}, socket)` that stores it. When a slot is picked and cadence is not `"once"`, compute a preview:

```elixir
  def handle_event("pick_slot", %{"start" => iso}, socket) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    socket = assign(socket, :selected_slot, dt)

    case socket.assigns.cadence do
      "once" ->
        {:noreply, assign(socket, :series_preview, nil)}

      cadence ->
        interval = if cadence == "biweekly", do: 2, else: 1

        case Scheduling.preview_series(%{
               instrument_slug: socket.assigns.instrument_slug,
               duration_minutes: socket.assigns.duration_minutes,
               first_starts_at: dt,
               interval_weeks: interval
             }) do
          {:ok, preview} -> {:noreply, assign(socket, :series_preview, preview)}
          {:error, _} -> {:noreply, assign(socket, :series_preview, nil)}
        end
    end
  end
```

Update `handle_event("book", ...)` to branch on cadence: for `"once"` call `create_booking/1` (existing); otherwise call `Scheduling.create_series/1` with the same details + `first_starts_at: selected_slot` + `interval_weeks`, and on success assign a `:booked_series` summary (count + conflicted weeks) for the confirmation step.

Render (within Track A's Schedule + Confirmed steps): a cadence radio group; when `@series_preview`, a summary line — e.g. `"#{length(@series_preview.bookable)} lessons through June 30 · #{length(@series_preview.conflicted)} weeks need another time"`; and on the Confirmed step, list the booked count and any conflicted weeks (Track B3 will make those actionable).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio_web/live/booking_live_recurring_test.exs`
Expected: PASS. Adjust the slot-selection line to match Track A's button markup.

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio_web/live/booking_live.ex test/music_studio_web/live/booking_live_recurring_test.exs
git commit -m "Offer weekly/bi-weekly series with a preview in BookingLive"
```

---

## B2 — Skip, pause, cancel a series

### Task 7: `skip_occurrence/1` and `cancel_series/1`

**Files:**
- Modify: `lib/music_studio/scheduling.ex`
- Test: `test/music_studio/scheduling/series_manage_test.exs`

**Interfaces:**
- Produces: `Scheduling.get_series_by_token(token) :: Enrollment.t() | nil`; `Scheduling.list_series_lessons(Enrollment.t()) :: [Lesson.t()]` (upcoming scheduled, ascending); `Scheduling.skip_occurrence(lesson_token) :: {:ok, Lesson.t()} | {:error, term()}` (cancels one lesson; series still holds the slot); `Scheduling.cancel_series(series_token) :: {:ok, Enrollment.t()} | {:error, term()}` (enrollment → `:cancelled` + soft-delete, all future scheduled lessons cancelled + Google events deleted; slot no longer held).

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/scheduling/series_manage_test.exs
defmodule MusicStudio.Scheduling.SeriesManageTest do
  use MusicStudio.DataCase, async: false

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "T", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google", refresh_token: "rt", access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c", target_calendar_id: "c"
      })

    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          day = conn.query_params["timeMin"] |> String.slice(0, 10)
          Req.Test.json(conn, %{"items" => [%{
            "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
            "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
          }]})

        _ -> Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)

    first = Scheduling.Recurrence.occurrence_utc(~D[2027-06-01], ~T[16:00:00], "America/Vancouver")
    {:ok, series} = Scheduling.create_series(%{instrument_slug: "piano", duration_minutes: 60, first_starts_at: first, interval_weeks: 1, name: "Sam", email: "sam@example.com", phone: nil})
    %{series: series}
  end

  test "skip one occurrence: that lesson is cancelled, the series remains", %{series: %{lessons: lessons, enrollment: enr}} do
    target = hd(lessons)
    assert {:ok, skipped} = Scheduling.skip_occurrence(target.booking_token)
    assert skipped.status == :cancelled
    assert Scheduling.get_series_by_token(enr.booking_token).status == :active
  end

  test "cancel series: enrollment cancelled and future lessons cancelled", %{series: %{enrollment: enr}} do
    assert {:ok, cancelled} = Scheduling.cancel_series(enr.booking_token)
    assert cancelled.status == :cancelled
    assert Enum.empty?(Scheduling.list_series_lessons(cancelled))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/series_manage_test.exs`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement the functions**

Add to `lib/music_studio/scheduling.ex`:

```elixir
  @spec get_series_by_token(String.t()) :: Enrollment.t() | nil
  def get_series_by_token(token), do: Repo.get_by(Enrollment, booking_token: token)

  @spec list_series_lessons(Enrollment.t()) :: [Lesson.t()]
  def list_series_lessons(%Enrollment{id: id}) do
    Repo.all(
      from l in Lesson,
        where: l.enrollment_id == ^id and l.status == :scheduled and is_nil(l.deleted_at),
        order_by: [asc: l.scheduled_start]
    )
  end

  @spec skip_occurrence(String.t()) :: {:ok, Lesson.t()} | {:error, term()}
  def skip_occurrence(lesson_token) do
    case get_lesson_by_token(lesson_token) do
      nil -> {:error, :not_found}
      lesson -> do_cancel(lesson)
    end
  end

  @spec cancel_series(String.t()) :: {:ok, Enrollment.t()} | {:error, term()}
  def cancel_series(series_token) do
    case get_series_by_token(series_token) do
      nil -> {:error, :not_found}
      enrollment -> do_cancel_series(enrollment)
    end
  end

  defp do_cancel_series(enrollment) do
    Enum.each(list_series_lessons(enrollment), &do_cancel/1)

    enrollment
    |> Teaching.change_enrollment(%{status: :cancelled, deleted_at: DateTime.utc_now()})
    |> Repo.update()
  end
```

`skip_occurrence` reuses `do_cancel/1` (cancels the lesson + deletes its Google event); the enrollment stays `:active`, so `held_intervals/2` keeps the slot reserved. `do_cancel/1` and `get_lesson_by_token/1` already exist.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/series_manage_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling.ex test/music_studio/scheduling/series_manage_test.exs
git commit -m "Add skip_occurrence and cancel_series to Scheduling"
```

---

### Task 8: `pause_series/2` — skip up to a month, hold the slot

**Files:**
- Modify: `lib/music_studio/scheduling.ex`
- Test: append to `test/music_studio/scheduling/series_manage_test.exs`

**Interfaces:**
- Produces: `Scheduling.pause_series(series_token, from_date :: Date.t()) :: {:ok, %{skipped: [Lesson.t()]}} | {:error, :too_long | :not_found}`. Cancels the next **≤4 consecutive** scheduled occurrences on/after `from_date`; the enrollment stays `:active` so the slot stays held and lessons resume afterward. More than 4 → `{:error, :too_long}` is impossible to trigger from the UI (it offers ≤4), but the guard is enforced here.

- [ ] **Step 1: Write the failing test** (append)

```elixir
  test "pause skips up to 4 consecutive occurrences and holds the slot", %{series: %{enrollment: enr}} do
    from = enr.started_on
    assert {:ok, %{skipped: skipped}} = Scheduling.pause_series(enr.booking_token, from)
    assert length(skipped) <= 4
    assert Enum.all?(skipped, &(&1.status == :cancelled))
    # enrollment still active -> slot still held
    assert Scheduling.get_series_by_token(enr.booking_token).status == :active
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/series_manage_test.exs`
Expected: FAIL — `pause_series/2` undefined.

- [ ] **Step 3: Implement `pause_series/2`**

```elixir
  @pause_max 4

  @spec pause_series(String.t(), Date.t()) :: {:ok, map()} | {:error, term()}
  def pause_series(series_token, from_date) do
    case get_series_by_token(series_token) do
      nil ->
        {:error, :not_found}

      enrollment ->
        to_skip =
          enrollment
          |> list_series_lessons()
          |> Enum.filter(&(Date.compare(DateTime.to_date(&1.scheduled_start), from_date) != :lt))
          |> Enum.take(@pause_max)

        skipped = Enum.map(to_skip, fn lesson -> {:ok, l} = do_cancel(lesson); l end)
        {:ok, %{skipped: skipped}}
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/series_manage_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling.ex test/music_studio/scheduling/series_manage_test.exs
git commit -m "Add pause_series (skip up to a month, hold the slot)"
```

---

### Task 9: `BookingManageLive` — series management UI

**Files:**
- Modify: `lib/music_studio_web/live/booking_manage_live.ex`
- Test: `test/music_studio_web/live/booking_manage_live_test.exs`

**Interfaces:**
- Consumes: `Scheduling.get_series_by_token/1`, `get_lesson_by_token/1`, `list_series_lessons/1`, `skip_occurrence/1`, `pause_series/2`, `cancel_series/1`, `cancel_booking/1`.
- Produces: `/book/manage/:token` resolves the token to a **series** (enrollment) or a **single lesson**; a series shows the upcoming occurrences with per-week **Skip**, a **Pause** control (choose a start week, up to 4), and **Cancel series**; a single lesson keeps the existing Cancel.

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio_web/live/booking_manage_live_test.exs
defmodule MusicStudioWeb.BookingManageLiveTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)
    {:ok, _} = Catalog.create_teacher(%{name: "T", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})
    {:ok, _} = Credentials.upsert(%{provider: "google", refresh_token: "rt", access_token: "at", access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second), availability_calendar_id: "c", target_calendar_id: "c"})
    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" -> day = conn.query_params["timeMin"] |> String.slice(0, 10); Req.Test.json(conn, %{"items" => [%{"start" => %{"dateTime" => day <> "T15:00:00-07:00"}, "end" => %{"dateTime" => day <> "T18:00:00-07:00"}}]})
        _ -> Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)
    first = Scheduling.Recurrence.occurrence_utc(~D[2027-06-01], ~T[16:00:00], "America/Vancouver")
    {:ok, series} = Scheduling.create_series(%{instrument_slug: "piano", duration_minutes: 60, first_starts_at: first, interval_weeks: 1, name: "Sam", email: "sam@example.com", phone: nil})
    %{series: series}
  end

  test "a series manage page lists upcoming lessons and can skip one", %{conn: conn, series: %{enrollment: enr, lessons: lessons}} do
    {:ok, view, html} = live(conn, "/book/manage/#{enr.booking_token}")
    assert html =~ "Your lesson series"
    target = hd(lessons)
    render_click(view, "skip", %{"token" => target.booking_token})
    refute render(view) =~ target.booking_token
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio_web/live/booking_manage_live_test.exs`
Expected: FAIL — no series branch / no "skip" handler.

- [ ] **Step 3: Implement the manage LiveView**

In `mount/3`, resolve the token to a series or lesson:

```elixir
  def mount(%{"token" => token}, _session, socket) do
    case Scheduling.get_series_by_token(token) do
      nil -> mount_single(token, socket)
      series -> mount_series(series, socket)
    end
  end

  defp mount_series(series, socket) do
    {:ok,
     socket
     |> assign(:kind, :series)
     |> assign(:series, series)
     |> assign(:lessons, Scheduling.list_series_lessons(series))
     |> assign(:cancelled, false)}
  end

  defp mount_single(token, socket) do
    {:ok,
     socket
     |> assign(:kind, :single)
     |> assign(:token, token)
     |> assign(:lesson, Scheduling.get_lesson_by_token(token))
     |> assign(:cancelled, false)}
  end
```

Add handlers `"skip"` (calls `skip_occurrence/1`, refreshes `:lessons`), `"pause"` (calls `pause_series/2` with a chosen from-date, refreshes), `"cancel_series"` (calls `cancel_series/1`), and keep the single `"cancel"`. Render a `:series` branch listing `@lessons` (local time via `DateTime.shift_zone!`) each with a Skip button (`phx-value-token={lesson.booking_token}`), a Pause control, and Cancel series; keep the `:single` branch as-is.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio_web/live/booking_manage_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio_web/live/booking_manage_live.ex test/music_studio_web/live/booking_manage_live_test.exs
git commit -m "Add series management (skip/pause/cancel) to BookingManageLive"
```

---

## B3 — Alternates for conflicted weeks

### Task 10: Offer + confirm an alternate slot for a conflicted week

**Files:**
- Modify: `lib/music_studio/scheduling.ex` (add `week_alternates/2` and `add_series_lesson/2`)
- Modify: `lib/music_studio_web/live/booking_live.ex` (render conflicted weeks with an alternate picker on the Confirmed step)
- Test: `test/music_studio/scheduling/alternates_test.exs`

**Interfaces:**
- Produces: `Scheduling.week_alternates(%{instrument_slug, duration_minutes}, week_of :: Date.t()) :: {:ok, [Slot.t()]}` — open slots in the Mon–Sun week containing `week_of`. `Scheduling.add_series_lesson(series_token, starts_at :: DateTime.t()) :: {:ok, Lesson.t()} | {:error, term()}` — books one more lesson into the series (shares `enrollment_id`, price snapshot, per-lesson token, Google event).

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/scheduling/alternates_test.exs
defmodule MusicStudio.Scheduling.AlternatesTest do
  use MusicStudio.DataCase, async: false

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)
    {:ok, _} = Catalog.create_teacher(%{name: "T", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})
    {:ok, _} = Credentials.upsert(%{provider: "google", refresh_token: "rt", access_token: "at", access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second), availability_calendar_id: "c", target_calendar_id: "c"})
    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" -> day = conn.query_params["timeMin"] |> String.slice(0, 10); Req.Test.json(conn, %{"items" => [%{"start" => %{"dateTime" => day <> "T15:00:00-07:00"}, "end" => %{"dateTime" => day <> "T18:00:00-07:00"}}]})
        _ -> Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)
    first = Scheduling.Recurrence.occurrence_utc(~D[2027-06-01], ~T[16:00:00], "America/Vancouver")
    {:ok, series} = Scheduling.create_series(%{instrument_slug: "piano", duration_minutes: 60, first_starts_at: first, interval_weeks: 1, name: "Sam", email: "sam@example.com", phone: nil})
    %{series: series}
  end

  test "week_alternates returns open slots that week and add_series_lesson books one", %{series: %{enrollment: enr}} do
    {:ok, slots} = Scheduling.week_alternates(%{instrument_slug: "piano", duration_minutes: 60}, ~D[2027-06-08])
    assert slots != []
    alt = hd(slots)
    assert {:ok, lesson} = Scheduling.add_series_lesson(enr.booking_token, alt.starts_at)
    assert lesson.enrollment_id == enr.id
    assert lesson.status == :scheduled
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/alternates_test.exs`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement `week_alternates/2` and `add_series_lesson/2`**

```elixir
  @spec week_alternates(map(), Date.t()) :: {:ok, [Availability.Slot.t()]} | {:error, term()}
  def week_alternates(%{instrument_slug: slug, duration_minutes: duration}, week_of) do
    monday = Date.add(week_of, -(Date.day_of_week(week_of) - 1))
    list_available_slots(%{instrument_slug: slug, duration_minutes: duration, from: monday, to: Date.add(monday, 6)})
  end

  @spec add_series_lesson(String.t(), DateTime.t()) :: {:ok, Lesson.t()} | {:error, term()}
  def add_series_lesson(series_token, starts_at) do
    with %Enrollment{} = enr <- get_series_by_token(series_token),
         enr <- Repo.preload(enr, :offering),
         ends_at <- DateTime.add(starts_at, enr.offering.duration_minutes, :minute),
         {:ok, lesson} <-
           %Lesson{}
           |> Lesson.changeset(%{
             scheduled_start: DateTime.truncate(starts_at, :second),
             scheduled_end: DateTime.truncate(ends_at, :second),
             duration_minutes: enr.offering.duration_minutes,
             status: :scheduled,
             price_cents: enr.offering.price_cents,
             currency: enr.offering.currency,
             teacher_id: enr.teacher_id,
             student_id: enr.student_id,
             instrument_id: enr.instrument_id,
             offering_id: enr.offering_id,
             enrollment_id: enr.id,
             booking_token: gen_token()
           })
           |> Repo.insert() do
      side_effect(fn -> add_series_event(enr, lesson, ends_at) end)
      {:ok, lesson}
    else
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{errors: errors}} -> booking_error(errors)
    end
  end

  defp add_series_event(enr, lesson, ends_at) do
    GoogleCalendar.insert_event(target_calendar(), %{
      summary: "Lesson — #{enr.contact_email}",
      description: "Series alternate.",
      location: "Studio",
      starts_at: lesson.scheduled_start,
      ends_at: ends_at,
      timezone: cfg(:studio_timezone),
      attendee_email: enr.contact_email,
      send_updates: "all"
    })
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/alternates_test.exs`
Expected: PASS (1 test).

- [ ] **Step 5: Wire the UI (Confirmed step)**

In `booking_live.ex`, when `@booked_series` has conflicted weeks, render each with a "Pick another time this week" button that loads `week_alternates/2` (a `handle_event("week_alternates", %{"week" => iso_date}, socket)`), shows the slots, and a `handle_event("add_alternate", %{"start" => iso}, socket)` that calls `add_series_lesson/2` and drops the week from the conflicted list. Keep it optional — skipping is fine.

- [ ] **Step 6: Run the LiveView test + commit**

Run: `mix test test/music_studio_web/live/booking_live_recurring_test.exs`
Expected: PASS.

```bash
git add lib/music_studio/scheduling.ex lib/music_studio_web/live/booking_live.ex test/music_studio/scheduling/alternates_test.exs
git commit -m "Offer and book alternate slots for conflicted series weeks"
```

---

## B4 — Summer follow-up (DESIGN ONLY — deferred)

**Not implemented in this track.** Captured so the data exists (`enrollments.contact_email`, `ended_on`, `status`).

**Goal (future):** after a series' `ended_on` (June 30), email active-series contacts inviting summer lessons.

**Options:**
- **Oban** (`{:oban, "~> 2.18"}` + a migration for its tables) — a `SummerFollowupWorker` scheduled via Oban Cron to scan for enrollments whose `ended_on` just passed and whose contact hasn't been emailed; robust, retryable, the right long-term answer.
- **Minimal cron** — a small `GenServer` that wakes daily (or a `mix music_studio.summer_followup` task run by an external scheduler) and sends via `Scheduling.Notifier`. No new dep; less robust.

**Recommendation:** defer until a job runner is wanted app-wide; add Oban then and reuse it for other periodic work. A single deferred task:

- [ ] **(Deferred) Add a summer-followup job** — add Oban (or the minimal GenServer), a query for `enrollments` with `ended_on` in the last N days and `status: :active`, and a `Notifier.deliver_summer_followup/1` email; record an Analytics `summer_followup_sent` event; guard against double-send with a per-enrollment flag or an Analytics lookup.

---

## Self-Review

**Spec coverage:** recurrence columns on Enrollment (T1); term-end + projection + DST (T2); slot-holding across skip/pause with no change to `Availability.compute/1` (T3); preview classification (T4); series creation as one transaction + side effects (T5); recurring option in the booking UI (T6); skip + cancel (T7); pause ≤4 holding the slot (T8); manage UI (T9); alternates for conflicted weeks (T10); summer follow-up designed + deferred (B4). Weekly/bi-weekly, Sept–Jun term, book-available-offer-alternates, pause-a-month-hold-slot — all covered.

**Deferred per the umbrella plan:** referral coupon; guardian/student split; styling the studio notification; the per-day Google fetch in `preview_series` (works; a whole-term single-fetch optimization is noted as a follow-up).

**Type consistency:** interval shape `%{starts_at, ends_at}` (UTC) matches `booked_intervals/2` and `Availability`; `preview_series/1` and `create_series/1` share the `first_starts_at`/`interval_weeks` params; `get_series_by_token/1`, `list_series_lessons/1`, `skip_occurrence/1`, `pause_series/2`, `cancel_series/1`, `week_alternates/2`, `add_series_lesson/2` names are used consistently across the context and the two LiveViews.

**Edge cases documented:** a skipped week's held slot is enforced only in the public availability path, not the DB constraint (add to `lessons.md`); DST handled in `Recurrence.occurrence_utc/3` (ambiguous → earlier, gap → after); booker kept as `contact_email` (guardian/student split later).

## Verification (end-to-end)

Use this session's local-dev harness (npm blocked — copy binaries, don't download):
1. `cp ../music_studio/_build/esbuild-darwin-arm64 _build/` and `cp ../music_studio/_build/tailwind-macos-arm64-4.3.0 _build/`.
2. `env -u DATABASE_URL mix ecto.migrate && env -u DATABASE_URL mix run priv/repo/seeds.exs`.
3. Recreate the git-ignored `config/dev.secret.exs` Google stub returning per-day availability blocks + seed one `scheduling_credentials` row.
4. `env -u DATABASE_URL PORT=4010 mix phx.server`; at `/book`: choose Piano + 60 min → **Weekly** → pick a time → confirm the preview lists the term; book; see the series email + `.ics` at `/dev/mailbox`; reopen `/book` and confirm the recurring time is **held** on future weeks; at `/book/manage/<series-token>` **skip** one week and **pause** a month and confirm the slot stays held; a conflicted week offers an alternate.
5. `mix precommit` green.
