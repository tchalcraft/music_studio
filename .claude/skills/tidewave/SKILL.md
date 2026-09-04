---
name: tidewave
description: Tidewave, the dev-only runtime-intelligence MCP server for this Phoenix app — lets a coding agent introspect, eval code, query the DB, and read logs against the *running* dev server. Use when setting up or using Tidewave, connecting an agent to the running app, or touching the dev tooling in the endpoint. Triggers on tidewave, /tidewave/mcp, project_eval, execute_sql_query, get_logs, get_docs, get_source_location, MCP dev server, allow_remote_access, allowed_origins.
when_to_use: Reach for this to connect an agent to the live dev app or change how Tidewave is mounted. For the SQL/Ecto queries you'd run through it use phoenix-foundations; for plain IEx/test mechanics use elixir-gotchas.
paths: mix.exs, lib/music_studio_web/endpoint.ex, config/dev.exs
---

# Tidewave — runtime intelligence for the dev app

Tidewave turns the **running dev server** into an MCP server so an agent can evaluate
Elixir in the live app, run SQL against the dev DB, read logs, and locate source. It is a
development tool only — never enabled in prod.

## How it's wired (already done)

- `mix.exs` — dev-only dependency:

      {:tidewave, "~> 0.9", only: :dev},

- `lib/music_studio_web/endpoint.ex` — mounted **inside** the `if code_reloading? do`
  block, so it loads only when code reloading is on (dev), never in a release:

      if code_reloading? do
        plug Tidewave
        socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
        # …
      end

The `only: :dev` dep guard **and** the `code_reloading?` plug guard are both deliberate —
keep both. If you ever move the plug, keep it inside a dev-only guard.

## Using it

1. Start the server: `mix phx.server` (or `iex -S mix phx.server`).
2. The MCP endpoint is `http://localhost:4000/tidewave/mcp`. It **honors `PORT`**, so a
   parallel `wt` worktree started with `PORT=4001 mix phx.server` exposes
   `http://localhost:4001/tidewave/mcp` — point each agent at the right port.
3. Add it to an editor/agent as an **HTTP (streamable) MCP** server at that URL. Claude
   Code, pi, Codex, VS Code, Cursor, and Neovim all support this transport.

Smoke-test without an editor:

    curl -sN http://localhost:4000/tidewave/mcp \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'

## Tools it exposes

- `project_eval` — evaluate Elixir inside the live app (IEx-like); the fastest way to
  check real behavior against real data.
- `execute_sql_query` — run SQL against the **dev** DB (Neon-backed here).
- `get_docs` — docs pinned to the exact versions in `mix.lock`.
- `get_logs` — recent server logs / telemetry.
- `get_source_location` — file/line for a module or function.
- Optional browser tools (`browser_eval`, design canvas) when enabled.

## Safety

- **Localhost only by default.** Do not expose it publicly. Only pass
  `allow_remote_access: true` (and scope `allowed_origins`) when you genuinely intend
  remote access — it grants code eval + DB access to whoever can reach the endpoint.
- Tidewave **relaxes the dev CSP** (`unsafe-eval`, frame-ancestors) so browser tools work.
  That is fine for dev and another reason it must never load in prod.
- The dev DB is real data (Neon). `execute_sql_query` writes are real writes — prefer
  read-only queries unless you mean it.

## Troubleshooting

- Editor can't connect → `curl` the endpoint first (above). Check the server is actually
  running, the `PORT` matches, and IPv4/IPv6 (`localhost` vs `127.0.0.1`).
- Nothing at `/tidewave/mcp` → confirm you're in `:dev` (the plug is behind
  `code_reloading?`) and `mix deps.get` pulled `tidewave`.

Related: [[phoenix-foundations]] (Ecto/SQL you'll run through it), [[elixir-gotchas]]
(IEx/eval and test mechanics).
