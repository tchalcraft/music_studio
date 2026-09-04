---
name: property-testing
description: Property-based testing for this Phoenix app at two layers — server-side StreamData/ExUnitProperties (Elixir, in test/) and browser Bombadil, the Antithesis autonomous browser property tester (TypeScript, in e2e/, run via CI). Use when writing or debugging property tests or generators, or when a bug is really an invariant that example tests keep missing. Triggers on use ExUnitProperties, check all, gen all, StreamData, property, generator, shrinking, max_runs, --seed, invariant, round-trip, Bombadil, @antithesishq/bombadil, always(), e2e specs.
when_to_use: Reach for this when the correctness claim is "for all inputs …" rather than one example. For plain ExUnit/test process mechanics (start_supervised!, Process.monitor, :sys.get_state) use elixir-gotchas; for LiveView test helpers use phoenix-liveview; for Ecto queries/changesets under test use phoenix-foundations.
paths: test/**/*.exs, e2e/**/*.ts, lib/**/*.ex
---

# Property-based testing

This app tests invariants at two complementary layers. Both express "for **all** inputs,
X holds" and let a tool hunt the counterexample:

- **Server-side — StreamData** (`ExUnitProperties`), Elixir, in `test/`. `stream_data` is
  already a dep (`~> 1.4`). Fast, precise, runs in `mix test` / `mix precommit`.
- **Browser — Bombadil** ([Antithesis](https://antithesishq.github.io/bombadil/browser/1-introduction.html)),
  TypeScript, in `e2e/`. Drives a real browser, explores the app, and checks temporal
  `always(...)` invariants. Runs in CI (`.github/workflows/bombadil.yml`), not `mix test`.

Use StreamData for logic/data/DB guarantees; use Bombadil for end-to-end UX guarantees
(the flow never crashes, never strands the visitor). They overlap on intent, not on level.

## Server-side: StreamData

Model after the real property test — `test/music_studio/scheduling/availability_property_test.exs`,
which pins the four guarantees of `MusicStudio.Scheduling.Availability.compute/1`
(grid-alignment, containment, min-notice, no-overlap) for *any* blocks/bookings/rules:

    use ExUnit.Case, async: true
    use ExUnitProperties

    property "every computed slot stays grid-aligned, in-block, past min-notice, non-overlapping" do
      check all args <- args_gen() do
        for slot <- Availability.compute(args) do
          assert grid_aligned?(slot.starts_at, args.grid_minutes)
          assert within_any_block?(slot, args.blocks)
          # …min-notice + no-overlap…
        end
      end
    end

Generators you'll reach for: `integer/0..1`, `member_of/1`, `one_of/1`, `constant/1`,
`list_of/1` (cap with `max_length:`), `string/1`, `tuple/1`, `fixed_map/1`. Build
**domain generators** with `gen all` rather than raw primitives — the real test's
`interval_gen`/`args_gen` are the pattern to copy. Compose with:

- `bind/2` — a generator that depends on a prior value (prefer over filtering).
- `filter/2` — drop invalid draws; use sparingly, it wastes runs and weakens shrinking.
- `map/2` — transform a generated value.

### Shrinking & determinism

- On failure StreamData **shrinks** to a minimal counterexample and prints it with the
  seed. Reproduce exactly with `mix test --seed N` (or `mix test path:line --seed N`).
- Tune per property: `check all x <- gen, max_runs: 200 do … end`. Keep runs bounded so
  `mix precommit` stays fast; raise them locally when hunting a rare case.
- Keep generators shrinkable: `gen all` / `bind` compose cleanly; heavy `filter` yields
  counterexamples that barely shrink.

### With Ecto / the DB

- Use the SQL Sandbox as usual (`Ecto.Adapters.SQL.Sandbox`); keep the property
  `async: true` only when the sandbox is shared for that test.
- The system under test is often a **changeset**: generate field maps with `fixed_map/1`
  and assert `changeset.valid?` matches your validation rules for all draws.

### Anti-patterns

- **Never** `String.to_atom/1` on generated data (unbounded atoms — memory leak). Use
  `String.to_existing_atom/1`, or `member_of/1` over a fixed set.
- Don't over-`filter`; reshape with `gen all`/`bind`/`map` instead.
- Don't leave `max_runs` unbounded in `mix precommit`.

## Browser: Bombadil (Antithesis)

`e2e/README.md` is the source of truth — read it before touching `e2e/`. In short:

- Specs live in `e2e/specs/*.spec.ts` and import `{ extract, always, actions, weighted }`
  from `@antithesishq/bombadil`. `extract(fn)` reads state into a cell (`.current`);
  `always(fn)` is a temporal invariant that must hold at every explored state;
  `actions`/`weighted` tell Bombadil how to drive the UI.
- It points at a **URL**: locally against `mix phx.server` (dev DB, never prod), or in CI
  against the deployed site via `bombadil.yml` (`workflow_dispatch` + weekly).
- **Not yet safe to fire against prod unattended:** the specs submit *real* inquiries and
  bookings, so `bombadil.yml` against the live domain is currently a deferred, manual-only
  smoke test. Point it at a dev/staging origin, or make the specs side-effect-free, before
  letting the weekly schedule hit prod.
- **It can't run from a Databricks-network machine** — the corp proxy blocks the npm
  registry and the site's domain. Run it from CI or a personal machine.
- The specs are written against Bombadil **v0.7.x** primitives; the exact import path and
  action payload shapes (`Fill`/`Click`/`Select`) are to be **confirmed on the first CI
  run**. If you touch a spec, verify the installed API rather than trusting the scaffold.

Keep the layers honest: hard guarantees (no double-booking, slots within working hours)
belong in the StreamData + DB tests; Bombadil specs guard the *UX* (never crash, never
strand the visitor), where precise assertions aren't feasible.

## Discipline — invariants over examples

Name the invariant, then let the tool try to break it. This is the defect class both
layers catch: the evening-slot double-booking bug (a `America/Vancouver`→UTC window that
crossed the day boundary) was exactly a `compute/1` invariant no per-day example test
exercised. Write server properties as *generate → apply → assert the invariant on the
result*; write browser properties as `always(...)` over an explored session. Deterministic
seeds make any StreamData failure replayable.

Related: [[elixir-gotchas]] (ExUnit + test process mechanics), [[phoenix-liveview]]
(LiveView test helpers), [[phoenix-foundations]] (changesets/queries under test).
