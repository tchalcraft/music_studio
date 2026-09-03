# Google Auth Pivot — OAuth → Service Account — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the Google Calendar **OAuth** flow (per-user consent + stored refresh token + one-time connect route) with a **service account**: the app mints its own access tokens from a service-account key and reads/writes a calendar that's been *shared* with the service account. No consent screen, no verification, no 7-day token expiry.

**Why:** The app only ever touches the teacher's own calendar and is operated by one person. Google's OAuth consent-screen + verification requirements (and the 7-day refresh-token expiry in "Testing") are pure overhead for that. Decision reverses the original "OAuth connect" choice in `2026-09-01-lesson-scheduling-design.md`.

**Architecture (why this is a small, safe change):** Everything that talks to Google goes through two stable seams — `MusicStudio.Scheduling.Credentials.fresh_access_token/0` and the `MusicStudio.Scheduling.GoogleCalendar` client. This pivot swaps only the *token-minting internals* behind `fresh_access_token/0`, plus config and the (now-removed) connect route. All booking / series / skip / pause / cancel code that calls `GoogleCalendar` keeps working unchanged.

**Tech Stack:** Elixir ~> 1.18, `Req` (reuses the existing `:scheduling_req_options` test seam), pure-OTP `:public_key` for RS256 JWT signing (no new dependency).

## Preconditions (READ FIRST)

- **Execute only AFTER Track B (recurring) has landed** on the `scheduling` branch. Track B edits `scheduling.ex` / `google_calendar.ex` call sites; this plan touches a couple of the same functions (attendee removal, Task 5). **Re-read the current `scheduling.ex`, `google_calendar.ex`, and `credentials.ex` before editing** — the diffs below name functions, not line numbers, and must be applied against the post-Track-B code.
- The stable auth files this mostly edits — `google_auth.ex`, `credentials.ex`, `credential.ex`, `config/*.exs`, `google_oauth_controller.ex`, `router.ex` — are **not** modified by Track B, so they match this plan as written.

## Global Constraints

- `music_studio.scheduling` worktree; jj+git colocated (commit with `git commit`, trailer `Co-authored-by: Isaac <no-reply@databricks.com>`).
- `mix precommit` green (`compile --warnings-as-errors --force`, `skills.check`, `deps.unlock --unused`, `format`, `gettext.extract --check-up-to-date`, `credo --strict` — nesting ≤2, alpha alias order — `sobelow`, `test`).
- Tests use local Postgres (`config/test.exs`) and stub all Google HTTP via the **existing** `:scheduling_req_options` → `{Req.Test, GoogleAuth}` seam. No live calls.
- Never commit the service-account key. Dev: `config/dev.secret.exs` (git-ignored). Prod: env var `GOOGLE_SERVICE_ACCOUNT_KEY` (JSON), read in `runtime.exs`.

## Known consequence (already agreed with the user)

A service account on a **personal Gmail** cannot send Google's native invite emails to attendees (that needs Workspace domain-wide delegation). So booked events land on the teacher's calendar but the **visitor is not invited via Google** — they rely on the Resend confirmation + `.ics` (Track C). Task 5 removes the attendee/`sendUpdates` bits accordingly. This also eliminates the earlier "two emails" concern.

---

### Task 1: Config — service-account key + calendar ids replace the OAuth keys

**Files:** `config/config.exs`, `config/runtime.exs`, `config/dev.secret.example.exs`, `test/music_studio/scheduling/config_test.exs` (extend).

**Interfaces:** config under `:music_studio, MusicStudio.Scheduling` gains `service_account_key` (map | nil), `availability_calendar_id` (string | nil), `target_calendar_id` (string | nil); keeps `google_token_url`. Removes `google_client_id`, `google_client_secret`, `google_redirect_uri`, `google_auth_url`, `setup_token`.

- [ ] **Step 1: Write/extend the failing test** in `test/music_studio/scheduling/config_test.exs`:

```elixir
  test "scheduling config exposes the service-account keys" do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling)
    assert Keyword.has_key?(cfg, :service_account_key)
    assert Keyword.has_key?(cfg, :availability_calendar_id)
    assert Keyword.has_key?(cfg, :target_calendar_id)
    assert cfg[:google_token_url] == "https://oauth2.googleapis.com/token"
  end
```

- [ ] **Step 2: Run → FAIL** (`mix test test/music_studio/scheduling/config_test.exs`): keys absent.

- [ ] **Step 3: `config/config.exs`** — in the `config :music_studio, MusicStudio.Scheduling,` block, remove `google_auth_url`, `google_client_id`, `google_client_secret`, `google_redirect_uri`, `setup_token`; keep `google_token_url`; add:

```elixir
  service_account_key: nil,
  availability_calendar_id: nil,
  target_calendar_id: nil,
```

- [ ] **Step 4: `config/runtime.exs`** — in the prod Scheduling block, replace the `google_client_id`/`secret`/`redirect_uri`/`setup_token` lines with:

```elixir
    service_account_key:
      System.get_env("GOOGLE_SERVICE_ACCOUNT_KEY") && Jason.decode!(System.get_env("GOOGLE_SERVICE_ACCOUNT_KEY")),
    availability_calendar_id: System.get_env("GOOGLE_AVAILABILITY_CALENDAR_ID"),
    target_calendar_id:
      System.get_env("GOOGLE_TARGET_CALENDAR_ID") || System.get_env("GOOGLE_AVAILABILITY_CALENDAR_ID"),
```

(Keep the Resend/notify/website/social lines. Leave the `RESEND_API_KEY` mailer block that already exists on `main` after rebase — do not duplicate it.)

- [ ] **Step 5: `config/dev.secret.example.exs`** — replace the Google OAuth comment block with:

```elixir
# Google Calendar via a SERVICE ACCOUNT (no consent screen). Paste the downloaded
# service-account JSON key and the shared calendar id into config/dev.secret.exs:
#
#     config :music_studio, MusicStudio.Scheduling,
#       service_account_key: %{
#         "client_email" => "music-studio-booking@your-project.iam.gserviceaccount.com",
#         "private_key" => "<the PEM private_key string, copied verbatim from the JSON key>",
#         "token_uri" => "https://oauth2.googleapis.com/token"
#       },
#       availability_calendar_id: "…@group.calendar.google.com",
#       target_calendar_id: "…@group.calendar.google.com"
#
# Share that calendar with the service account's client_email ("Make changes to events").
```

- [ ] **Step 6: Run → PASS.** **Step 7: Commit** `git commit -m "Config: service-account key + calendar ids replace Google OAuth keys"`.

---

### Task 2: `GoogleAuth` — mint access tokens from the service-account key (RS256 JWT)

**Files:** `lib/music_studio/scheduling/google_auth.ex` (rewrite), `test/music_studio/scheduling/google_auth_test.exs` (rewrite).

**Interfaces:** Produces `GoogleAuth.mint_access_token() :: {:ok, %{access_token: String.t(), expires_at: DateTime.t()}} | {:error, term()}`. Keeps the `req/1` seam (merges `:scheduling_req_options`) unchanged. Removes `authorize_url/1`, `exchange_code/1`, `refresh/1`.

- [ ] **Step 1: Rewrite the test.** Generate an RSA key in-test so signing is real, build a fake SA key map, stub the token endpoint via the existing seam:

```elixir
defmodule MusicStudio.Scheduling.GoogleAuthTest do
  use ExUnit.Case, async: false

  alias MusicStudio.Scheduling.GoogleAuth

  setup do
    # A real (throwaway) RSA private key so JWT signing actually runs.
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, rsa)
    pem = :public_key.pem_encode([pem_entry])

    prev = Application.get_env(:music_studio, MusicStudio.Scheduling)

    Application.put_env(
      :music_studio,
      MusicStudio.Scheduling,
      Keyword.merge(prev,
        service_account_key: %{
          "client_email" => "svc@proj.iam.gserviceaccount.com",
          "private_key" => pem,
          "token_uri" => "https://oauth2.googleapis.com/token"
        }
      )
    )

    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})

    on_exit(fn ->
      Application.put_env(:music_studio, MusicStudio.Scheduling, prev)
      Application.delete_env(:music_studio, :scheduling_req_options)
    end)
  end

  test "mint_access_token signs a JWT, exchanges it, and returns a token" do
    Req.Test.stub(GoogleAuth, fn conn ->
      # Assert it's the jwt-bearer grant with a 3-part assertion.
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"
      assert body =~ "assertion="
      Req.Test.json(conn, %{"access_token" => "at-sa", "expires_in" => 3600})
    end)

    assert {:ok, %{access_token: "at-sa", expires_at: %DateTime{}}} = GoogleAuth.mint_access_token()
  end
end
```

- [ ] **Step 2: Run → FAIL** (`mint_access_token/0` undefined).

- [ ] **Step 3: Rewrite `google_auth.ex`:**

```elixir
defmodule MusicStudio.Scheduling.GoogleAuth do
  @moduledoc """
  Mints Google API access tokens from a service-account key via the JWT-bearer grant
  (RS256, signed with pure OTP `:public_key` — no extra dependency). Scope covers reading
  the Availability calendar and writing lesson events. Replaces the former OAuth flow.
  """
  @scope "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly"

  @spec mint_access_token() :: {:ok, map()} | {:error, term()}
  def mint_access_token do
    key = cfg(:service_account_key) || %{}
    token_uri = key["token_uri"] || cfg(:google_token_url)

    with {:ok, jwt} <- signed_jwt(key, token_uri) do
      form = %{
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => jwt
      }

      case Req.post(req(url: token_uri, form: form)) do
        {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
          {:ok, %{access_token: token, expires_at: DateTime.add(DateTime.utc_now(), body["expires_in"] || 3600, :second)}}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp signed_jwt(%{"client_email" => iss, "private_key" => pem}, aud) when is_binary(iss) and is_binary(pem) do
    now = System.system_time(:second)

    header = %{"alg" => "RS256", "typ" => "JWT"}
    claims = %{"iss" => iss, "scope" => @scope, "aud" => aud, "iat" => now, "exp" => now + 3600}

    signing_input = b64(Jason.encode!(header)) <> "." <> b64(Jason.encode!(claims))
    signature = :public_key.sign(signing_input, :sha256, private_key(pem))
    {:ok, signing_input <> "." <> b64(signature)}
  end

  defp signed_jwt(_key, _aud), do: {:error, :missing_service_account_key}

  defp private_key(pem) do
    [entry] = :public_key.pem_decode(pem)
    :public_key.pem_entry_decode(entry)
  end

  defp b64(bin), do: Base.url_encode64(bin, padding: false)

  @doc false
  def req(opts) do
    Req.new(opts) |> Req.merge(Application.get_env(:music_studio, :scheduling_req_options, []))
  end

  defp cfg(key), do: Keyword.get(Application.get_env(:music_studio, MusicStudio.Scheduling, []), key)
end
```

- [ ] **Step 4: Run → PASS. Step 5: Commit** `git commit -m "GoogleAuth: mint access tokens from a service-account key (JWT-bearer)"`.

---

### Task 3: `Credentials` — mint+cache via the service account; calendar ids from config

**Files:** `lib/music_studio/scheduling/credentials.ex` (rewrite), `test/music_studio/scheduling/google_auth_test.exs` or a `credentials_test.exs` (add a fresh_access_token test), and check `scheduling.ex`/`google_calendar.ex` call sites for `Credentials.get()` (see Task 4).

**Interfaces:** `Credentials.fresh_access_token/0` keeps its contract (`{:ok, token} | {:error, term()}`) but now mints via `GoogleAuth.mint_access_token/0`, caching in an Agent/ETS-free way — simplest: an in-process cache is overkill; just mint on demand (Google tokens last 1h; minting per request batch is fine) OR cache in the existing `scheduling_credentials` row. **Recommended: mint on demand** (drop the DB token cache) to delete the connect-flow/DB coupling entirely. Add `Credentials.availability_calendar_id/0` and `target_calendar_id/0` reading from config.

- [ ] **Step 1: Add the test** (mint-on-demand, config-sourced ids):

```elixir
  test "fresh_access_token mints via the service account" do
    # (same RSA-key + stub setup as GoogleAuthTest)
    Req.Test.stub(GoogleAuth, fn conn -> Req.Test.json(conn, %{"access_token" => "at-1", "expires_in" => 3600}) end)
    assert {:ok, "at-1"} = MusicStudio.Scheduling.Credentials.fresh_access_token()
  end

  test "calendar ids come from config" do
    assert MusicStudio.Scheduling.Credentials.availability_calendar_id() == "cal-x"
  end
```

(Set `availability_calendar_id: "cal-x"` in the test's config merge.)

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Rewrite `credentials.ex`:**

```elixir
defmodule MusicStudio.Scheduling.Credentials do
  @moduledoc """
  Hands out a currently-valid Google access token (minted from the service-account key)
  and the configured calendar ids. No stored refresh token / connect flow — the service
  account is authorized by sharing the calendar with it.
  """
  alias MusicStudio.Scheduling.GoogleAuth

  @spec fresh_access_token() :: {:ok, String.t()} | {:error, term()}
  def fresh_access_token do
    case GoogleAuth.mint_access_token() do
      {:ok, %{access_token: token}} -> {:ok, token}
      other -> other
    end
  end

  @spec configured?() :: boolean()
  def configured?, do: is_map(cfg(:service_account_key)) and is_binary(availability_calendar_id())

  @spec availability_calendar_id() :: String.t() | nil
  def availability_calendar_id, do: cfg(:availability_calendar_id)

  @spec target_calendar_id() :: String.t() | nil
  def target_calendar_id, do: cfg(:target_calendar_id) || cfg(:availability_calendar_id)

  defp cfg(key), do: Keyword.get(Application.get_env(:music_studio, MusicStudio.Scheduling, []), key)
end
```

- [ ] **Step 4: Update call sites** (against post-Track-B code): in `scheduling.ex`, `list_available_slots/1` currently gates on `Credentials.get()` returning a row with `availability_calendar_id` and reads it — change it to `Credentials.configured?()` + `Credentials.availability_calendar_id()`; `target_calendar/0` → `Credentials.target_calendar_id()`. In `google_calendar.ex`, no change (still uses `Credentials.fresh_access_token/0`). Grep `Credentials.get(` and replace each.

- [ ] **Step 5: Run → PASS (and the scheduling suite still green). Step 6: Commit** `git commit -m "Credentials: mint on demand + config calendar ids; drop stored token"`.

---

### Task 4: Remove the OAuth connect flow, controller, routes, and `Credential` schema/table

**Files:** delete `lib/music_studio_web/controllers/google_oauth_controller.ex`; edit `router.ex` (drop `/admin/google/connect` + `/oauth/google/callback`); delete `lib/music_studio/scheduling/credential.ex`; add a migration dropping `scheduling_credentials` (down = recreate); remove any controller test.

- [ ] **Step 1** Delete the controller + its test; remove the two routes from `router.ex`.
- [ ] **Step 2** Delete `credential.ex`. Grep for `Scheduling.Credential` / `scheduling_credentials` and remove remaining references (the `Credentials` module no longer uses the schema after Task 3).
- [ ] **Step 3** Generate a migration `drop_scheduling_credentials`: `drop table(:scheduling_credentials)` in `up`, recreate in `down` (copy the create from `20260901120000_add_scheduling.exs`).
- [ ] **Step 4** `mix test` — fix any references; the OAuth controller test is gone. **Step 5: Commit** `git commit -m "Remove Google OAuth connect flow, controller, routes, and credentials table"`.

---

### Task 5: Stop inviting the visitor via Google (personal-Gmail SA can't send invites)

**Files:** `lib/music_studio/scheduling/google_calendar.ex` (event body), and `scheduling.ex` `write_event/*` (drop `attendee_email`/`send_updates`). **Apply against post-Track-B code.**

- [ ] **Step 1** In `google_calendar.ex` `event_body/1`, drop the `"attendees"` field (or always `[]`), and change `insert_event`/`update_event`/`delete_event` `sendUpdates` param to `"none"`.
- [ ] **Step 2** In `scheduling.ex`, remove `attendee_email:`/`send_updates:` from the `write_event` map(s) (single + series). The Resend confirmation + `.ics` (Track C) remains the visitor's calendar path — unchanged.
- [ ] **Step 3** Update `google_calendar_test.exs` expectations (no attendees; `sendUpdates=none`). `mix test`. **Step 4: Commit** `git commit -m "Booked events: no Google attendee invite (service account); rely on Resend + ICS"`.

---

### Task 6: Full gate, docs, deploy re-coordination

- [ ] **Step 1** `mix precommit` → exits 0.
- [ ] **Step 2** Live check (dev): drop the real SA JSON key + calendar id into `config/dev.secret.exs`, `env -u DATABASE_URL PORT=4010 mix phx.server`, book a lesson at `/book`, confirm the event appears on the shared Google calendar and the Resend confirmation + `.ics` arrive at `/dev/mailbox`. (No `/admin/google/connect` step any more.)
- [ ] **Step 3** Update the design spec (`2026-09-01-lesson-scheduling-design.md`, Tristan repo) to record the OAuth→service-account reversal; note in `lessons.md` that personal-Gmail SAs can't send attendee invites.
- [ ] **Step 4** Re-message the `deploy-music-studio-render` session: the prod env vars change — **remove** `GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI/SETUP_TOKEN`; **add** `GOOGLE_SERVICE_ACCOUNT_KEY` (the JSON) and `GOOGLE_AVAILABILITY_CALENDAR_ID` (+ optional `GOOGLE_TARGET_CALENDAR_ID`). No redirect URI needed.

## Self-Review

**Coverage:** token minting (T2), token seam preserved so all calendar callers keep working (T3), calendar ids from config (T1, T3), connect flow/controller/routes/table removed (T4), attendee-invite consequence handled (T5), config + prod env + deploy coordination (T1, T6). **No new dependency** (RS256 via `:public_key`). **Test seam** (`:scheduling_req_options`) reused so Google stays stubbed. **Reversal** of the OAuth design decision is documented (T6).

**Depends on:** Track B landed first; re-read `scheduling.ex` / `google_calendar.ex` before Tasks 3–5.
