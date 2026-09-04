# Tidewave + property-testing skills

_2026-09-04_

> **Amendment (2026-09-04):** while this branch was in flight, `main` independently landed
> **Bombadil** — the [Antithesis](https://antithesishq.github.io/bombadil/) autonomous
> *browser* property tester — under `e2e/` with CI (`bombadil.yml`), plus a real
> StreamData property test (`availability_property_test.exs`). So the original "Bombadil is
> dropped / not a library" decision below is superseded: Bombadil is real and in the repo,
> just a different layer (browser E2E) from StreamData (server-side). The `property-testing`
> skill was revised to document **both** layers and to point at `e2e/README.md` as the
> source of truth for Bombadil. "Antithesis" is Bombadil's vendor, not a separate SDK.

## Context

The app already carries five project-local skills under `music_studio/.claude/skills/`
covering Elixir gotchas, Phoenix foundations (Ecto/router/HEEx/forms), LiveView
(streams/hooks/tests), client-vs-server interactions, and UI/Tailwind. Two areas the user
works in have no skill: **Tidewave** (a dev-time runtime-intelligence MCP server for
Phoenix) and **property-based testing**. `mix.exs` already depends on `stream_data`
(`~> 1.4`, `:dev`/`:test`) — the official Elixir property-testing library — but there is no
`tidewave` dependency.

Approved decisions:

- **Extend the project skill set, not a plugin.** Two new skills authored under
  `.claude/skills/`; no distributable plugin, no repackaging of the existing five.
- **Two skills, not one combined** — `tidewave` and `property-testing` fire in different
  situations.
- **Property testing rides on StreamData** (already installed). "Bombadil" is dropped;
  "Antithesis" is folded in as *thinking* (explicit invariants, deterministic seeds,
  shrinking, operation-sequence assertions) — no new test dependency, no Antithesis SDK.
- **Wire Tidewave into the app** (dev-only), not just document it.
- Work in an isolated worktree of the `music_studio` repo (changes are additive + two tiny
  dev-only edits that don't overlap the concurrent scheduling review).

## Skill 1 — `tidewave`

Dev-time runtime-intelligence MCP server for this Phoenix app.

- **Frontmatter**: `name`, `description` (triggers: `tidewave`, `/tidewave/mcp`,
  `project_eval`, `execute_sql_query`, `get_logs`, `get_docs`, `get_source_location`,
  "MCP dev server", `allow_remote_access`), `when_to_use`, `paths: mix.exs,
  lib/music_studio_web/endpoint.ex, config/dev.exs`.
- **Body**:
  - What Tidewave is and why (agents introspect / eval / query the *running* dev app).
  - The dev-only wiring as shipped: `{:tidewave, "~> 0.9", only: :dev}` in `mix.exs`;
    `plug Tidewave` inside the `if code_reloading? do` block in `endpoint.ex`.
  - The MCP endpoint: `http://localhost:4000/tidewave/mcp`; honors `PORT`, so parallel
    `wt` worktrees each expose their own (`PORT=4001` → `:4001/tidewave/mcp`).
  - Tools exposed: `project_eval`, `execute_sql_query`, `get_docs` (pinned to
    `mix.lock` versions), `get_logs`, `get_source_location`, optional browser tools.
  - Connecting this machine's agents (Claude Code, pi) as an HTTP/streamable MCP client.
  - Security: localhost-only by default; `allow_remote_access` caution; dev-only CSP
    relaxation (`unsafe-eval`); **never load in prod** (the `only: :dev` guard enforces it).
  - Troubleshooting: `curl` JSON-RPC `ping`, IPv4/IPv6, server must be running.
  - Cross-links: `[[elixir-gotchas]]`, `[[phoenix-foundations]]`.

## Skill 2 — `property-testing`

Property-based testing on StreamData, with Antithesis-style thinking.

- **Frontmatter**: triggers `use ExUnitProperties`, `check all`, `StreamData`, `property`,
  generators, shrinking, `max_runs`, `--seed`, "invariant"; `paths: test/**/*.exs,
  lib/**/*.ex`.
- **Body**:
  - When a property test beats example tests: invariants, round-trips, idempotence,
    oracle — grounded in this app's domain (scheduling intervals, changesets, Stripe
    amount-cents).
  - StreamData mechanics: `use ExUnitProperties`; `property "…" do check all x <- gen, do:
    assert … end`; built-in + composed generators (`bind`, `filter`, `member_of`,
    `list_of`); building domain generators (a booking-interval generator, a term-bounded
    date generator).
  - Shrinking & determinism: reproduce failures with `mix test --seed N`; tune `max_runs`
    / `initial_size`; how StreamData shrinks toward minimal counterexamples.
  - Antithesis-style guidance: state invariants explicitly and test *operation sequences*,
    using the two real booking bugs as motivating examples — evening-slot double-booking
    (UTC/`America/Vancouver` window mismatch) and series lessons scheduled past
    `term_end`. These are the exact defect class property tests catch.
  - Ecto integration: `Ecto.Adapters.SQL.Sandbox`, `async`, changeset-as-SUT.
  - Anti-patterns: never `String.to_atom` generated data; prefer `bind` over `filter`;
    cap runs in CI.
  - Cross-links: `[[elixir-gotchas]]` (test mechanics), `[[phoenix-liveview]]`
    (LiveView tests).

## App wiring (Tidewave)

1. `mix.exs`: add `{:tidewave, "~> 0.9", only: :dev}` (latest at build time — `mix hex.info
   tidewave` confirmed 0.9.0, 2026-08-18).
2. `endpoint.ex`: add `plug Tidewave` inside the existing `if code_reloading? do` block
   (currently line 38), dev-only.
3. `mix deps.get`; confirm `mix compile` is clean.

## Skills mirror

`.agents/skills` is a symlink → `../.claude/skills`, so new skills mirror automatically and
`mix skills.check` (wired into `mix precommit`) stays green. No manifest to edit.

## Verification

- `mix skills.check` passes (symlink intact, both new skills present in both trees).
- `mix compile` clean after the new dep.
- New SKILL.md frontmatter matches the existing five (`name` / `description` /
  `when_to_use` / `paths`).
- Optional: `curl` the `/tidewave/mcp` ping against a running `mix phx.server`.

## Out of scope (YAGNI)

- No Bombadil; no Antithesis platform/SDK.
- No property tests added to the app suite (the concurrent booking review is adding
  those); this skill is guidance only.
- No changes to the five existing skills.
- No distributable plugin.
