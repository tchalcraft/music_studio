# Track A — Guided Step-by-Step Booking Flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-page `/book` flow into a guided, stepped experience — a top progress bar plus one focused screen per step (Lesson → Schedule → Your details → Confirmed) — with Back navigation that never loses entered details, then dress it in the site's `ms-` brand tokens.

**Architecture:** Keep `MusicStudioWeb.BookingLive` a single LiveView with no router changes. Add a `:step` assign (`:lesson | :schedule | :details | :done`) advanced by the existing events, a local `step_bar/1` function component, per-step `<section>` render clauses, a `back` event, and a `validate_details` change handler that persists the details form across navigation. Step 2 ("Schedule") is intentionally a thin slot-picker screen so Track B can later add a single-vs-recurring choice there without another redesign.

**Tech Stack:** Elixir 1.18 / Phoenix ~> 1.7 / LiveView ~> 1.2, `Phoenix.LiveViewTest`, Tailwind v4 + the `ms-` token layer in `assets/css/app.css`.

**Spec:** `~/.claude/plans/i-want-to-change-goofy-honey.md` (Track A).

## Global Constraints

- Work in the **`music_studio.scheduling` worktree**; all paths are relative to it. The app is a submodule using **jj colocated with git** — `git commit` works normally.
- **`mix precommit` must stay green**: `compile --warnings-as-errors --force`, `skills.check`, `deps.unlock --unused`, `format`, `gettext.extract --check-up-to-date`, `credo --strict`, `sobelow`, `test`. Run it before each commit.
- **Phoenix ~> 1.7, LiveView ~> 1.2** — no 1.8-only APIs.
- **No router changes**; `/book` stays one LiveView. Reuse the existing `handle_event("choose", …)`, `"pick_slot"`, `"book"` bodies — only their resulting `:step` assign is new.
- Match the existing `ms-` design tokens (`--ms-accent #3e63dd`, neutrals, `--ms-radius`) from `assets/css/app.css`; don't introduce a second visual vocabulary.
- Reuse `MusicStudioWeb.CoreComponents` (`<.input>`, `<.icon>` with `hero-*` names) — don't hand-roll inputs or icons.

---

### Task 1: Step state machine, progress bar, and Back navigation

**Files:**
- Modify (rewrite): `lib/music_studio_web/live/booking_live.ex`
- Modify: `test/music_studio_web/live/booking_live_test.exs`

**Interfaces:**
- Produces: `:step` assign on `BookingLive` (`:lesson | :schedule | :details | :done`); a local component `step_bar(assigns)` (attr `current: atom`); events `"back"` (`%{"to" => step_string}`) and `"validate_details"` (`%{"booking" => params}`).
- Consumes (unchanged): `MusicStudio.Scheduling.list_available_slots/1`, `create_booking/1`; `MusicStudio.Catalog.list_instruments/0`, `list_offerings/0`.

- [ ] **Step 1: Write the failing tests**

Replace the body of `test/music_studio_web/live/booking_live_test.exs` with this (keeps the two existing assertions, adds the step-flow tests + a shared Google stub helper):

```elixir
defmodule MusicStudioWeb.BookingLiveTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  # First availability block is far in the future so it clears the 24h min-notice window.
  # 3:00–5:00 PM PT on 2027-01-05 (UTC-08:00) → 60-min/30-grid slots at 23:00, 23:30, 00:00Z.
  @first_slot_iso "2027-01-05T23:00:00Z"

  defp stub_google do
    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{
            "items" => [
              %{
                "start" => %{"dateTime" => "2027-01-05T15:00:00-08:00"},
                "end" => %{"dateTime" => "2027-01-05T17:00:00-08:00"}
              }
            ]
          })

        _ ->
          Req.Test.json(conn, %{"id" => "evt-test"})
      end
    end)
  end

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})
    {:ok, _} = Catalog.create_offering(%{name: "60", duration_minutes: 60, price_cents: 7000, active: true})

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google",
        refresh_token: "rt",
        access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c",
        target_calendar_id: "c"
      })

    :ok
  end

  test "renders the instrument + duration picker", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    assert html =~ "Book a lesson"
    assert html =~ "Piano"
  end

  test "the step bar shows all four steps with Lesson current on mount", %{conn: conn} do
    {:ok, view, html} = live(conn, "/book")
    assert html =~ "Schedule"
    assert html =~ "Your details"
    assert html =~ "Confirmed"
    assert has_element?(view, ~s([aria-current="step"]), "Lesson")
  end

  test "choosing instrument + duration advances to the Schedule step", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")

    html = render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    assert html =~ "Available times"
    assert has_element?(view, ~s([aria-current="step"]), "Schedule")
  end

  test "picking a slot advances to Your details", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    html = render_click(view, "pick_slot", %{"start" => @first_slot_iso})
    assert html =~ "Your name"
    assert has_element?(view, ~s([aria-current="step"]), "Your details")
  end

  test "completing the flow shows the Confirmed step", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_click(view, "pick_slot", %{"start" => @first_slot_iso})

    html =
      render_submit(view, "book", %{
        "booking" => %{"name" => "Sam Lee", "email" => "sam@example.com", "phone" => ""}
      })

    assert html =~ "You're booked!"
    assert has_element?(view, ~s([aria-current="step"]), "Confirmed")
  end

  test "Back from details returns to Schedule and keeps entered details", %{conn: conn} do
    stub_google()
    {:ok, view, _} = live(conn, "/book")
    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_click(view, "pick_slot", %{"start" => @first_slot_iso})
    render_change(view, "validate_details", %{"booking" => %{"name" => "Sam Lee", "email" => "", "phone" => ""}})

    render_click(view, "back", %{"to" => "schedule"})
    assert has_element?(view, ~s([aria-current="step"]), "Schedule")

    html = render_click(view, "pick_slot", %{"start" => @first_slot_iso})
    assert html =~ ~s(value="Sam Lee")
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/music_studio_web/live/booking_live_test.exs`
Expected: FAIL — the new tests can't find `[aria-current="step"]` / "Your details" step markup (the step bar and step machine don't exist yet).

- [ ] **Step 3: Rewrite `booking_live.ex` as a step machine**

Replace the entire contents of `lib/music_studio_web/live/booking_live.ex` with:

```elixir
defmodule MusicStudioWeb.BookingLive do
  @moduledoc """
  Public booking flow, presented as guided steps with a progress bar:
  Lesson → Schedule → Your details → Confirmed. Single LiveView, no route changes.
  """
  use MusicStudioWeb, :live_view

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling

  # Ordered steps as {key, label}; the index drives the progress bar and Back targets.
  @steps [lesson: "Lesson", schedule: "Schedule", details: "Your details", done: "Confirmed"]

  @impl true
  def mount(_params, _session, socket) do
    durations =
      Catalog.list_offerings()
      |> Enum.filter(& &1.active)
      |> Enum.map(& &1.duration_minutes)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok,
     socket
     |> assign(:page_title, "Book a lesson")
     |> assign(:step, :lesson)
     |> assign(:instruments, Catalog.list_instruments())
     |> assign(:durations, durations)
     |> assign(:instrument_slug, nil)
     |> assign(:duration_minutes, nil)
     |> assign(:slots, [])
     |> assign(:slots_error, nil)
     |> assign(:selected_slot, nil)
     |> assign(:booked, nil)
     |> assign(:form, to_form(%{"name" => "", "email" => "", "phone" => ""}, as: :booking))}
  end

  @impl true
  def handle_event("choose", %{"instrument_slug" => slug, "duration_minutes" => dur}, socket)
      when slug != "" and dur != "" do
    duration = String.to_integer(dur)
    today = DateTime.utc_now() |> DateTime.shift_zone!(studio_tz()) |> DateTime.to_date()

    socket = assign(socket, instrument_slug: slug, duration_minutes: duration, selected_slot: nil)

    case Scheduling.list_available_slots(%{
           instrument_slug: slug,
           duration_minutes: duration,
           from: today,
           to: Date.add(today, 28)
         }) do
      {:ok, slots} -> {:noreply, assign(socket, slots: slots, slots_error: nil, step: :schedule)}
      {:error, reason} -> {:noreply, assign(socket, slots: [], slots_error: inspect(reason), step: :schedule)}
    end
  end

  def handle_event("choose", %{"instrument_slug" => slug, "duration_minutes" => dur}, socket) do
    {:noreply,
     assign(socket,
       instrument_slug: blank_to_nil(slug),
       duration_minutes: parse_duration(dur),
       slots: [],
       selected_slot: nil,
       step: :lesson
     )}
  end

  def handle_event("pick_slot", %{"start" => iso}, socket) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    {:noreply, assign(socket, selected_slot: dt, step: :details)}
  end

  def handle_event("validate_details", %{"booking" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :booking))}
  end

  def handle_event("book", %{"booking" => params}, socket) do
    attrs = %{
      instrument_slug: socket.assigns.instrument_slug,
      duration_minutes: socket.assigns.duration_minutes,
      starts_at: socket.assigns.selected_slot,
      name: params["name"],
      email: params["email"],
      phone: params["phone"]
    }

    case Scheduling.create_booking(attrs) do
      {:ok, lesson} ->
        {:noreply, assign(socket, booked: lesson, step: :done)}

      {:error, :slot_taken} ->
        {:noreply,
         socket
         |> put_flash(:error, "Sorry — that time was just taken. Please pick another.")
         |> assign(selected_slot: nil, step: :schedule)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  def handle_event("back", %{"to" => to}, socket) do
    {:noreply, assign(socket, :step, String.to_existing_atom(to))}
  end

  ## Components

  attr :current, :atom, required: true

  def step_bar(assigns) do
    assigns = assign(assigns, :steps, @steps)

    ~H"""
    <ol class="mt-6 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm" aria-label="Booking progress">
      <li
        :for={{{key, label}, idx} <- Enum.with_index(@steps, 1)}
        class={["flex items-center gap-2", @current == key && "font-semibold text-indigo-700"]}
        aria-current={(@current == key && "step") || nil}
      >
        <span class={[
          "flex size-6 items-center justify-center rounded-full border text-xs",
          done?(@current, key) && "border-indigo-600 bg-indigo-600 text-white",
          !done?(@current, key) && @current == key && "border-indigo-600 text-indigo-700",
          !done?(@current, key) && @current != key && "border-gray-300 text-gray-400"
        ]}>
          <.icon :if={done?(@current, key)} name="hero-check-mini" class="size-4" />
          <span :if={!done?(@current, key)}>{idx}</span>
        </span>
        <span>{label}</span>
      </li>
    </ol>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl p-6">
      <h1 class="text-2xl font-semibold">Book a lesson</h1>

      <.step_bar current={@step} />

      <section :if={@step == :lesson} class="mt-6">
        <h2 class="font-medium">Choose your lesson</h2>
        <form id="booking-picker" phx-change="choose" class="mt-3 flex gap-4">
          <select name="instrument_slug" class="rounded border p-2">
            <option value="">Instrument…</option>
            <option :for={i <- @instruments} value={i.slug} selected={i.slug == @instrument_slug}>
              {i.name}
            </option>
          </select>
          <select name="duration_minutes" class="rounded border p-2">
            <option value="">Length…</option>
            <option :for={d <- @durations} value={d} selected={d == @duration_minutes}>
              {d} min
            </option>
          </select>
        </form>
      </section>

      <section :if={@step == :schedule} class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Available times</h2>
          <button type="button" phx-click="back" phx-value-to="lesson" class="text-sm text-indigo-700 underline">
            ← Back
          </button>
        </div>

        <p :if={@slots_error} class="mt-4 text-sm text-red-600">
          Couldn't load times. Please try again.
        </p>

        <p :if={!@slots_error and @slots == []} class="mt-4 text-sm text-gray-500">
          No open times in the next few weeks. Please check back soon.
        </p>

        <div class="mt-3 flex flex-wrap gap-2">
          <button
            :for={slot <- @slots}
            type="button"
            phx-click="pick_slot"
            phx-value-start={DateTime.to_iso8601(slot.starts_at)}
            class="rounded border px-3 py-1 hover:border-indigo-600"
          >
            {slot_label(slot.starts_at)}
          </button>
        </div>
      </section>

      <section :if={@step == :details} class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="font-medium">Your details</h2>
          <button type="button" phx-click="back" phx-value-to="schedule" class="text-sm text-indigo-700 underline">
            ← Back
          </button>
        </div>

        <p class="mt-2 text-sm text-gray-500">
          {slot_label(@selected_slot)} · {@duration_minutes} min
        </p>

        <.form for={@form} phx-change="validate_details" phx-submit="book" class="mt-4 space-y-3">
          <.input field={@form[:name]} label="Your name" required />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:phone]} label="Phone (optional)" />
          <button type="submit" class="rounded bg-indigo-600 px-4 py-2 text-white">
            Confirm booking
          </button>
        </.form>
      </section>

      <section :if={@step == :done} class="mt-6 rounded border p-4">
        <p class="font-medium">
          You're booked! Check your email for a confirmation and calendar invite.
        </p>
      </section>
    </div>
    """
  end

  ## Helpers

  defp step_index(step), do: Enum.find_index(@steps, fn {key, _} -> key == step end)

  # A step is "done" (shows a check) once the current step is past it.
  defp done?(current, key), do: step_index(current) > step_index(key)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp parse_duration(""), do: nil
  defp parse_duration(v), do: String.to_integer(v)

  defp studio_tz, do: Application.get_env(:music_studio, MusicStudio.Scheduling)[:studio_timezone]

  defp slot_label(dt) do
    dt |> DateTime.shift_zone!(studio_tz()) |> Calendar.strftime("%a %b %-d, %-I:%M %p")
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/music_studio_web/live/booking_live_test.exs`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the full gate**

Run: `mix precommit`
Expected: exits 0. If `credo --strict` flags `String.to_existing_atom/1` region or nesting, address minimally; `to_existing_atom` is safe here (all step atoms are compile-time constants) — keep it (do NOT switch to `String.to_atom/1`, which Sobelow flags).

- [ ] **Step 6: Commit**

```bash
git add lib/music_studio_web/live/booking_live.ex test/music_studio_web/live/booking_live_test.exs
git commit -m "Track A: step machine + progress bar + Back navigation for /book"
```

---

### Task 2: On-brand step styling and reduced motion

**Files:**
- Modify: `assets/css/app.css` (add an `ms-` step-bar component block)
- Modify: `lib/music_studio_web/live/booking_live.ex` (swap the step-bar utility classes for the `ms-` classes)
- Modify: `test/music_studio_web/live/booking_live_test.exs` (assert the branded markup renders)

**Interfaces:**
- Consumes: the `--ms-accent`, `--ms-border`, `--ms-text-muted`, `--ms-on-accent`, `--ms-radius` tokens already defined in `assets/css/app.css`.
- Produces: `.ms-stepbar`, `.ms-step`, `.ms-step-badge`, `.ms-step.is-current`, `.ms-step.is-done` classes.

- [ ] **Step 1: Write the failing test**

Add to `test/music_studio_web/live/booking_live_test.exs`:

```elixir
  test "the step bar uses the branded ms- classes", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    assert html =~ ~s(class="ms-stepbar")
    assert html =~ "ms-step"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/music_studio_web/live/booking_live_test.exs -k "branded ms-"`
(or run the file) — Expected: FAIL, `ms-stepbar` not in the markup yet.

- [ ] **Step 3: Add the step-bar styles to `app.css`**

Append to `assets/css/app.css`, alongside the other `ms-` component styles (after the token `:root` block). These derive entirely from existing tokens and disable the transition under reduced-motion:

```css
/* Booking progress bar — see BookingLive. Tokens defined above in :root / [data-theme]. */
.ms-stepbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem 1rem;
  margin-top: 1.5rem;
  padding: 0;
  list-style: none;
  font-size: 0.875rem;
  color: var(--ms-text-muted);
}
.ms-step {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.ms-step-badge {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: 999px;
  border: 1px solid var(--ms-border);
  font-size: 0.75rem;
  transition: background-color 120ms ease, border-color 120ms ease, color 120ms ease;
}
.ms-step.is-current { color: var(--ms-text); font-weight: 600; }
.ms-step.is-current .ms-step-badge { border-color: var(--ms-accent); color: var(--ms-accent-text); }
.ms-step.is-done .ms-step-badge {
  border-color: var(--ms-accent);
  background: var(--ms-accent);
  color: var(--ms-on-accent);
}
@media (prefers-reduced-motion: reduce) {
  .ms-step-badge { transition: none; }
}
```

- [ ] **Step 4: Swap the step-bar markup to the `ms-` classes**

In `lib/music_studio_web/live/booking_live.ex`, replace the `step_bar/1` `~H` block with:

```elixir
    ~H"""
    <ol class="ms-stepbar" aria-label="Booking progress">
      <li
        :for={{{key, label}, idx} <- Enum.with_index(@steps, 1)}
        class={["ms-step", step_status(@current, key)]}
        aria-current={(@current == key && "step") || nil}
      >
        <span class="ms-step-badge">
          <.icon :if={done?(@current, key)} name="hero-check-mini" class="size-4" />
          <span :if={!done?(@current, key)}>{idx}</span>
        </span>
        <span>{label}</span>
      </li>
    </ol>
    """
```

And add the `step_status/2` helper next to `done?/2`:

```elixir
  defp step_status(current, key) do
    cond do
      current == key -> "is-current"
      done?(current, key) -> "is-done"
      true -> "is-todo"
    end
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/music_studio_web/live/booking_live_test.exs`
Expected: PASS (7 tests).

- [ ] **Step 6: Run the full gate**

Run: `mix precommit`
Expected: exits 0.

- [ ] **Step 7: Commit**

```bash
git add assets/css/app.css lib/music_studio_web/live/booking_live.ex test/music_studio_web/live/booking_live_test.exs
git commit -m "Track A: style the booking step bar with ms- tokens + reduced motion"
```

---

## Self-Review

**Spec coverage (Track A):** progress bar (Task 1 `step_bar` + Task 2 styling); one screen per step with `:step` machine (Task 1 render clauses); Back without losing details (Task 1 `back` + `validate_details`, verified by the "keeps entered details" test); single LiveView / no router change (unchanged mount + routes); `ms-` brand tokens + reduced motion (Task 2). Step 2 "Schedule" is a standalone screen ready for Track B's single-vs-recurring choice.

**Placeholder scan:** none — every step ships complete code and exact commands.

**Type consistency:** `:step` atoms (`:lesson/:schedule/:details/:done`) match `@steps` keys and the `back` event's `String.to_existing_atom/1`; `step_index/1`, `done?/2`, `step_status/2` all key off the same `@steps` list.

## Manual verification (optional live check)

Use this session's local-dev harness (npm blocked, so copy binaries): `cp ../music_studio/_build/esbuild-darwin-arm64 _build/` and `cp ../music_studio/_build/tailwind-macos-arm64-4.3.0 _build/`; `env -u DATABASE_URL mix ecto.migrate && env -u DATABASE_URL mix run priv/repo/seeds.exs`; recreate the git-ignored `config/dev.secret.exs` Google stub + a `scheduling_credentials` row; `env -u DATABASE_URL PORT=4010 mix phx.server`; open `http://localhost:4010/book` and confirm the progress bar advances Lesson → Schedule → Your details → Confirmed, Back preserves typed details, and the bar matches the site's indigo/slate theme in light and dark.
