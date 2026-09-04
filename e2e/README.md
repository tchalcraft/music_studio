# Browser property tests (Bombadil)

Autonomous browser property testing with [Bombadil](https://antithesishq.github.io/bombadil/browser/1-introduction.html).
Bombadil drives a real browser against a running site, explores it, and checks the
**invariants** declared in `specs/` (temporal `always(...)` properties) — a complement to
the server-side ExUnit + StreamData tests, aimed at the end-to-end UX of the two critical
flows:

- **`specs/inquiry.spec.ts`** — the home-page inquiry form never crashes and reaches a
  confirmation (regression guard for GH #3).
- **`specs/booking.spec.ts`** — the `/book` flow never crashes and never strands the
  visitor on a blank/stuck page.

## Where it runs

Bombadil points at a **URL** (`bombadil browser test … <origin>`). Two targets:

- **Local** — against `mix phx.server` (`http://localhost:4000`). Point the server at the
  Neon **dev** branch, never production.
- **Deployed** — against `https://tristanchalcraftmusic.com`, via the
  **`.github/workflows/bombadil.yml`** manual workflow. Run it by hand right after each
  manual deploy as a smoke test.

> ⚠️ **This can't run from a Databricks-network machine:** the corporate proxy blocks the
> npm registry (so `npm install` fails) *and* the `tristanchalcraftmusic.com` domain
> (newly-registered-domain category). Run it from CI (GitHub runners) or a personal
> machine. That's also why the deployed run lives in GitHub Actions.

## Local run (non-corporate network)

```sh
cd e2e
npm install                       # installs @antithesishq/bombadil
# Bombadil also needs its CLI binary — see the install docs:
#   https://antithesishq.github.io/bombadil/browser/2.1-installation.html
# Start the app in another terminal first: (from ../ ) mix phx.server
npm run test:browser:local        # drives http://localhost:4000, results in ./results
```

## Status / caveats

The specs are written against Bombadil's **documented v0.7.x** primitives
(`extract` / `always` / `actions` / `weighted`, cell values via `.current`). The exact
import path and action-payload shapes (`Fill` / `Click` / `Select`) should be **confirmed
on the first CI run** and adjusted if the installed version's API differs — this is the
first time the tool runs in this project, and it couldn't be validated locally (proxy
block above). Treat the first `bombadil.yml` run as the validation step; expand the specs
(more extractors, tighter invariants) once the API is confirmed.
