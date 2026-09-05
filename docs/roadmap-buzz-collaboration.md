# Buzz Collaboration Platform: Integration Roadmap & API Guide

**Date:** 2026-09-04  
**Status:** Research & planning (no implementation yet)  
**Verification:** Facts verified against [github.com/block/buzz](https://github.com/block/buzz) as of 2026-09-04.

---

## 1. What Is Buzz?

**Buzz** is a self-hosted, open-source collaborative workspace platform built on the Nostr protocol by Block, Inc. It is licensed under **Apache 2.0**.

### Core Model

Buzz treats **humans and AI agents as first-class workspace members** with equal cryptographic standing:

- Every action (message, reaction, workflow step, approval, git event) becomes a signed Nostr event in a unified immutable log.
- Users and agents authenticate via **Nostr keypairs** (secp256k1 Schnorr signatures), not usernames/passwords.
- The platform provides **channels** (persistent topic-based spaces), **DMs** (peer-to-peer), **voice huddles** (real-time audio), **YAML workflows** (automated multi-step processes), and **media storage** (images, video, files).

### Architecture Snapshot

- **Backend:** Rust relay with WebSocket (stateful, full-duplex) and HTTP (stateless) interfaces
- **Primary storage:** PostgreSQL (events, search, workflow/channel metadata); Redis (pub/sub, presence, typing); S3-compatible storage (media blobs)
- **Frontend:** Desktop (Tauri + React), CLI tools, agent SDKs
- **Deployment:** One-click Railway setup, Docker Compose production bundle, or local development; self-hosted, no vendor lock-in

---

## 2. Fit for Music Studio: Honest Assessment

### ✅ Strong Fit

**Student–Teacher Collaboration Channels**  
Channels map naturally to studio use:
- Private studio channel per student (student, teacher, optionally parent for minors)
- Shared teacher channels for peer-to-peer coaching, lesson planning, or teacher training
- Public channels for studio announcements, group classes, or recital coordination

Benefits: Persistent message history, searchable transcripts, media attachments (sheet music, recordings, photos), and no "where was that file?" problem.

**Agent-Generated Lesson Plans**  
Agents in Buzz have cryptographic keys and channel membership, enabling:
- A lesson-planning agent to join a student's channel, analyze practice history/feedback, and draft personalized lesson plans
- Review/approval workflows (teacher approves, agent refines, student gets pinged with updates)
- Audit trail: every suggestion and decision is cryptographically signed and immutable

This is fundamentally different from traditional chatbots—agents are *members* of the workspace, not external API calls.

### ⚠️ Partial/Needs External Piece

**Capturing Live-Session Audio & Transcription**  
Buzz supports **voice huddles** (in-progress; "huddle lifecycle events" marked as being wired up on the main repo as of 2026-09-04), but:

- **Recording is NOT built in.** Huddles carry live audio, but storing/transcribing the session requires an external service.
- **No native transcription.** You'll need a separate pipeline (e.g., OpenAI Whisper, LiveKit, Deepgram) to convert audio to text.

**Workarounds:**
1. **Record externally during huddle:** Have students/teachers use a separate recorder (e.g., Riverside.fm, Zencastr) during the lesson, then upload the session to a shared channel after the lesson ends.
2. **Students upload practice recordings:** Instead of live huddle recording, ask students to upload practice audio files to a channel before the lesson; the agent transcribes offline.
3. **Run transcription as a sidecar service:** If you self-host Buzz with a voice infrastructure (e.g., LiveKit), build a recording agent that joins huddles, saves streams to S3, and triggers async Whisper transcription—but this is custom work outside Buzz's current feature set.

**Bottom line:** Huddles are a viable meeting space, but session capture and transcription are *not* built in to Buzz. This is the area requiring the most custom engineering.

---

## 3. How to Configure & Integrate via the API

### 3.1 Core Identity: Nostr Keypairs

Buzz has no username/password. Every identity is a **Nostr keypair**:

- **Private key (`nsec`):** 32-byte secret used to sign events; held by the actor (human or agent).
- **Public key (`npub`):** 64-character hex or Bech32-encoded identifier; publicly visible, safe to share.

**For the music_studio app:**
- Each user (student, teacher, parent) gets a keypair—can be generated server-side at signup or imported from external wallet.
- Each AI agent (lesson planner, feedback generator) gets its own keypair—generated at deployment, stored securely (e.g., in a CI secret or hardware key).

**Do NOT hardcode or commit private keys.** Store as environment variables or secrets manager.

### 3.2 Authentication Paths

#### **Path A: WebSocket + NIP-42 (Full-Featured, Stateful)**

This is the primary path for agents and desktop clients.

```
1. Client connects to wss://your-relay-domain/
2. Relay sends: ["AUTH", "<random-challenge>"]
3. Client signs challenge with its Nostr private key, responds: ["AUTH", <event>]
   - Event kind 27235 (NIP-98) or challenge-specific format
   - Signature is Schnorr over the challenge bytes
   - Timestamp tolerance: ±60 seconds to prevent replay
4. Relay validates signature and grants stateful subscriptions
   - Full 14 scopes unlocked on successful auth
```

**When to use:** Real-time agent subscriptions, live huddle presence, typing indicators, persistent connection state. Best for agents that need to stay connected and reactive.

#### **Path B: HTTP + NIP-98 (Stateless, Fire-and-Forget)**

For one-off API calls from backend services (e.g., Phoenix app posting on behalf of a teacher).

```
1. Caller signs a "kind:27235" event with:
   - "method": "POST" (or GET, PUT, DELETE)
   - "u": "https://relay-domain/query"
   - Other tags: "p" (pubkey), "exp" (expiry), etc.
   - Signature: Schnorr over canonical event serialization
2. Caller sends HTTP request:
   POST /query
   Authorization: Nostr <event>
3. Relay verifies signature and event ID independently
4. On success, relay processes request (e.g., query events, submit event)
```

**When to use:** Stateless REST-style operations from the Phoenix backend (recording a lesson, querying history). No connection state to manage.

**Endpoint summary** (verified against [ARCHITECTURE.md](https://raw.githubusercontent.com/block/buzz/main/ARCHITECTURE.md)):

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `/` | WebSocket → NIP-42 | Primary relay; SUBSCRIBE/EVENT/AUTH messages |
| `/.well-known/nostr.json` | None | NIP-05 identity discovery |
| `/events`, `/query`, `/count` | HTTP + NIP-98 | Stateless event submission & filtering |
| `/hooks/{id}` | Secret | Webhook triggers for workflows |
| `/media/upload`, `/media/{sha256}` | NIP-98 | Blossom-protocol media storage |

### 3.3 Self-Hosted Stack Requirements

To run Buzz for your studio:

**Infrastructure:**
- **PostgreSQL 13+** with monthly range partitioning (Buzz handles auto-setup); GIN index on `search_tsv` for full-text search. ~100 GB recommended for 100K+ events.
- **Redis 6+** for pub/sub fan-out, presence (180-second TTL), typing indicators (5-second window).
- **S3-compatible storage** (MinIO, AWS S3, or Digital Ocean Spaces) with 50 GB+ capacity for media. Max upload is 50 MB per file.

**Container/runtime:**
- Docker Compose bundle in [`deploy/compose/`](https://github.com/block/buzz/tree/main/deploy/compose) (verified entry point).
- Or: Railway one-click deployment for quick team relays.
- Rust workspace compiles on macOS (Intel/Apple Silicon), Linux (x86_64), Windows (x64).

**Deployment path for music_studio:**
Most likely **Docker Compose on Render** (your current host) or a separate lightweight VPS:
- `docker-compose up -d` spins up Postgres + Redis + Buzz relay + MinIO
- Expose relay on `https://relay.your-domain.music:443` (requires TLS cert, e.g., Let's Encrypt)
- Phoenix backend → talks to relay via NIP-98 HTTP or spawns agent subprocesses connected via NIP-42

### 3.4 Environment Configuration

Buzz relay reads `.env` or environment variables. **Key sections** (verified against [.env.example](https://raw.githubusercontent.com/block/buzz/main/.env.example)):

> ⚠️ **Re-verify at implementation time.** Buzz ships frequently; treat the exact variable names and values below as illustrative of the current shape, and confirm them against the repo's `.env.example` when you actually wire this up.

#### **Database**
```bash
# A postgres URL of the form: scheme://USER:PASSWORD@HOST:5432/buzz_relay
DATABASE_URL=<your-buzz-relay-postgres-url>
# Optional read replica (same URL shape, pointed at the replica host)
READ_DATABASE_URL=<your-buzz-relay-replica-url>
# Tuning
BUZZ_DB_POOL_SIZE=20              # max connections per pool
BUZZ_DB_STATEMENT_TIMEOUT_MS=5000 # per-statement timeout
```

#### **Redis & Search**
```bash
REDIS_URL=redis://localhost:6379
BUZZ_REDIS_POOL_SIZE=10
TYPESENSE_URL=http://localhost:8108
TYPESENSE_API_KEY=<admin-api-key>
```

#### **Relay Identity & Binding**
```bash
BUZZ_BIND_ADDR=0.0.0.0:8080           # listen on all interfaces, port 8080
RELAY_URL=wss://relay.your-domain.music # public WebSocket URL for clients
BUZZ_RELAY_PRIVATE_KEY=<32-byte-hex>   # stable relay signing key
BUZZ_WEB_DIR=/app/dist                 # web UI distribution path
```

#### **S3 Media Storage**
```bash
BUZZ_S3_ENDPOINT=https://minio.your-domain.music
BUZZ_S3_ACCESS_KEY=<minio-access-key>
BUZZ_S3_SECRET_KEY=<minio-secret-key>
BUZZ_S3_BUCKET=buzz-media
BUZZ_S3_REGION=us-east-1
BUZZ_S3_ADDRESSING_STYLE=path  # or "virtual"
```

#### **Rate Limiting** (protect relay from abuse)
```bash
BUZZ_RATE_LIMIT_HUMAN_MESSAGES_PER_MIN=60
BUZZ_RATE_LIMIT_HUMAN_API_CALLS_PER_MIN=300
BUZZ_RATE_LIMIT_AGENT_STANDARD_MESSAGES_PER_MIN=120
BUZZ_RATE_LIMIT_AGENT_STANDARD_API_CALLS_PER_MIN=600
```

#### **Agent Communication (ACP)**
If running agents in-process:
```bash
BUZZ_PRIVATE_KEY=<agent-private-key-hex>     # REQUIRED
BUZZ_RELAY_URL=wss://relay.your-domain.music # where agent connects
BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/claude # AI agent binary path
BUZZ_ACP_AGENTS=4                             # spawn 4 parallel agent instances
BUZZ_ACP_MODEL=claude-opus-4                  # LLM model
BUZZ_ACP_TURN_TIMEOUT=30                      # max seconds per turn
BUZZ_ACP_MAX_TURNS_PER_SESSION=20             # max turns before reset
BUZZ_ACP_SYSTEM_PROMPT_FILE=/etc/buzz/system-prompt.txt
```

### 3.5 Integration Pattern: Phoenix ↔ Buzz Relay

**Scenario:** A Phoenix LiveView or endpoint needs to post a message to Buzz on behalf of a teacher.

#### Step 1: Generate Teacher's Nostr Keypair
At signup or import, generate a keypair:
```elixir
# In music_studio/lib/music_studio/buzz/keys.ex
defmodule MusicStudio.Buzz.Keys do
  def generate_keypair() do
    # Use a Nostr Elixir client (e.g., nostr-ex or custom BLAKE3+Schnorr)
    # Returns {private_key_hex, public_key_hex}
    {:ok, private, public}
  end

  def store_user_key(user_id, private_key) do
    # Store in encrypted secrets table, never log
  end
end
```

#### Step 2: Sign an NIP-98 Event
When posting to Buzz relay:
```elixir
# In a Phoenix controller or context
defmodule MusicStudio.Buzz.Client do
  def post_message_to_relay(channel_id, message_text, user_nostr_pubkey) do
    # 1. Construct NIP-98 event
    event = %{
      "kind" => 1,  # text note
      "pubkey" => user_nostr_pubkey,
      "created_at" => System.unix_time(),
      "tags" => [
        ["e", channel_id],  # link to channel
        ["p", user_nostr_pubkey]
      ],
      "content" => message_text
    }

    # 2. Compute event ID (SHA256 of canonical JSON)
    event_id = compute_event_id(event)
    event = Map.put(event, "id", event_id)

    # 3. Sign with Schnorr (requires libsecp256k1 Elixir bindings)
    signature = sign_schnorr(event, user_private_key)
    event = Map.put(event, "sig", signature)

    # 4. POST to relay with NIP-98 Authorization header
    headers = [
      {"Authorization", "Nostr #{Jason.encode!(event)}"},
      {"Content-Type", "application/json"}
    ]

    # This app already depends on Req — use it (no HTTPoison/hackney).
    Req.post("https://relay.your-domain.music/events", json: event, headers: headers)
  end
end
```

**Note:** The Schnorr signing part requires crypto primitives. Options:
- Elixir + `libsecp256k1` via NIF (e.g., the `secp256k1` hex package)
- Call out to a sidecar (e.g., `buzz-cli` binary over IPC)
- Use a Node.js bridge if hex packages are not available (least preferred)

Verify exact library names and versions against [Buzz's Rust dependencies](https://github.com/block/buzz/blob/main/crates/buzz-core/Cargo.toml) and Elixir ecosystem.

---

## 4. Differentiator Vision: The Feedback Loop

The true power emerges when you combine Buzz's collaborative infrastructure with external AI services to close a feedback loop:

```
┌─────────────────┐
│ Student         │
│ practices piano,│
│ uploads audio   │
│ to Buzz channel │
└────────┬────────┘
         │
         ▼
┌──────────────────────────┐
│ External transcription   │
│ service (Whisper, etc.)  │
│ → generates text         │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────────────────────┐
│ Lesson-planning agent joins channel,     │
│ reads practice + transcript, generates:  │
│ - personalized feedback                  │
│ - next-week lesson plan                  │
│ - exercises to focus on                  │
│ Posts as structured message              │
└────────┬─────────────────────────────────┘
         │
         ▼
┌───────────────────┐
│ Student sees      │
│ plan + feedback   │
│ in their channel  │
│ Practices more    │
│ Loop repeats      │
└───────────────────┘
```

**What Buzz provides:**
- Channel membership & persistence (student, teacher, agent all in one place)
- Cryptographic audit trail (every suggestion signed, immutable)
- Real-time notifications (agent posts plan → student gets pinged)
- Media storage (scores, recordings, reference videos)

**What you build:**
- Transcription pipeline (integrate Whisper, LiveKit, or Deepgram)
- Lesson-plan agent logic (could be a Claude/GPT/local LLM, via Buzz's ACP or external HTTP bridge)
- UI surface in music_studio to read/respond to channel messages (could mirror Buzz UI or create custom view)

**Why this matters:**
- **Scalability:** One teacher ÷ many students; agent handles personalization at scale.
- **Asynchrony:** Practice happens on student time; feedback waits in channel (no live meeting required).
- **Trust & transparency:** Cryptographically signed suggestions; teacher can review/override before delivery.
- **Engagement:** Students see their progress tracked over time; the channel becomes a practice journal.

---

## 5. Phased Roadmap

### Phase 1: Channels for Collaboration (1–2 sprints)

**Goal:** Establish student–teacher communication.

**Build:**
- Buzz relay deployed (self-hosted on Render or separate VPS)
- Keypair generation & storage for each user/teacher
- Music Studio UI: embed or iframe Buzz web client, or build a minimal channel browser in LiveView
- Backend: Phoenix endpoints to create channels (teacher + student), manage membership
- Tests: verify keypair generation, relay connectivity, basic message flow

**Effort:** ~2 weeks (assumes you hire or partner with Nostr/Rust expertise for relay ops; Elixir integration is straightforward).

**Dependencies:** Buzz deployment, TLS cert, S3 or MinIO storage.

**Verification:** Teacher and student can see each other's messages in a private channel; media uploads work.

### Phase 2: Agent-Generated Lesson Plans (2–3 sprints)

**Goal:** Deploy a lesson-planning agent that generates personalized feedback.

**Build:**
- Agent keypair & deployment (run `buzz-acp` subprocess or external service)
- Lesson-plan prompt engineering (what context → what output; test with Claude API)
- Logic to parse practice history, prior feedback, and generate next-week plan
- Trigger: teacher approves a previous lesson, or student marks a piece "ready for review"
- Workflow: agent joins channel, posts draft plan, teacher approves/tweaks, student is notified
- Tests: prompt quality, agent response latency, approval workflow

**Effort:** ~2–3 weeks (LLM integration + workflow orchestration).

**Dependencies:** Phase 1 complete; access to Claude API or local LLM; agent credentials stored securely.

**Verification:** Agent generates sensible lesson plans; teacher can review and approve before student sees them; plans appear in student's channel.

### Phase 3: Session Capture & Transcription (3–4 sprints)

**Goal:** Record & transcribe lessons, feed transcripts back into the feedback loop.

**Build:**
- **Huddle recording**: Decide on one of:
  - **External service:** Integrate Riverside.fm, Zencastr, or LiveKit into the lesson booking flow; automatically share recording URL in Buzz channel post-lesson.
  - **Sidecar recording agent:** If you self-host Buzz with LiveKit, build a recording agent that joins huddles, streams to S3, and triggers transcription.
  - **Student upload:** Skip live huddle recording; have students upload practice audio post-lesson for async transcription.

- **Transcription pipeline**: Integrate Whisper (OpenAI API or self-hosted), Deepgram, or equivalent:
  - Trigger: audio file posted to channel or recording available from external service
  - Output: structured transcript (text + optional speaker labels, timecode)
  - Post back to channel as message or attachment

- **Agent feedback v2:** Update agent prompt to ingest lesson transcript:
  - "Here's what student played today (transcript + notes), here's their goal, here's last week's plan: draft feedback and next week's focus."

- **Tests:** transcription accuracy, agent response quality given transcripts, end-to-end integration.

**Effort:** ~3–4 weeks (most work is integration, not Buzz-specific).

**Dependencies:** Phase 2 complete; choice of recording service; Whisper/transcription API access; S3 storage capacity.

**Gotchas:**
- Huddles are "in progress" in Buzz (as of 2026-09-04); verify with current repo before committing.
- Recording adds latency & cost; choose recording method carefully (real-time vs. post-hoc upload).
- Transcription accuracy varies by audio quality and speaker (singing ≠ speech); may require custom post-processing.

**Verification:** Lesson recorded → transcript appears in channel → agent reads transcript and generates improved feedback.

---

## 6. Consent, Privacy & Legal Gating (REQUIRED Before Any Capture)

### Before Any Audio/Video Recording

This section is **non-negotiable.** Recording lessons—especially those involving minors—triggers significant legal and ethical obligations.

#### 6.1 Jurisdiction & Regulations

Check your local laws:

- **US (varies by state):**
  - California: "Two-party consent" (all participants must agree to recording).
  - New York: "Two-party consent" (all participants must agree).
  - Florida, Illinois, others: "Two-party consent."
  - Consent can be in writing or expressed (e.g., on-screen acknowledgment).
  - Failure to obtain consent can be a criminal misdemeanor.

- **EU (GDPR & ePrivacy Directive):**
  - Recording is processing of personal data; requires a lawful basis (consent is most straightforward).
  - If children under 13 are involved, parental consent may be required (varies by member state).
  - Data must have a purpose; retention must be limited.

- **Canada (PIPEDA, provincial privacy laws):**
  - Consent required for recording; teacher's consent alone is insufficient if students are recorded.
  - Applies even to teacher's own recordings for lesson feedback.

#### 6.2 Consent Framework

**Before implementing Phase 3:**

1. **Consent document** (written or in-app):
   - Clear statement: "Your lesson may be recorded for transcription and AI-generated feedback."
   - Checkbox: "I consent to recording and transcription."
   - Separate checkbox: "I consent to AI analysis of my performance."
   - Date & timestamp the consent.

2. **If minors are involved:**
   - Student (minor) consent is not sufficient; **guardian/parent consent required**.
   - Provide simplified language for the student; full legal language for the parent.
   - Store consent with a date; respect withdrawal requests immediately.

3. **Data retention policy:**
   - Define: "Audio will be stored for 30 days; transcripts for 1 year."
   - Or: "Audio deleted after transcription; transcript kept for 3 years."
   - Provide UI for users to request deletion anytime.
   - **Honor deletion requests within 30 days.** (GDPR, CCPA.)

4. **Access control:**
   - Define who can access recordings/transcripts:
     - Student: always (their own data)
     - Teacher: always (their own data + their students' with consent)
     - Admin: only for technical support (log accesses)
     - External services (Whisper, etc.): only raw audio, anonymized if possible
   - **Do NOT share a student's recording with other teachers or unauthenticated users.**

5. **Data security:**
   - Encrypt audio at rest (S3 server-side encryption, AES-256, or client-side before upload).
   - Use TLS for all transmission.
   - Rotate access keys quarterly.
   - Log all access attempts (who, what, when).
   - Plan breach notification: if recording leaked, notify affected users within 72 hours.

#### 6.3 Operational Checklist

Before deploying Phase 3:

- [ ] Legal review: have a lawyer review your consent form and retention policy for your jurisdiction.
- [ ] Consent UI: implement in-app consent flow with date-stamped checkboxes.
- [ ] Retention automation: code a scheduled job to delete old recordings per policy.
- [ ] Deletion workflow: implement user-initiated "delete my recording" endpoint; test it.
- [ ] Parental consent (if applicable): separate form/UI for guardians.
- [ ] Transparency: privacy policy updated; explain recording, transcription, agent analysis; link from the lesson booking flow.
- [ ] Audit log: log all recording access; export quarterly for compliance review.
- [ ] Incident response: document what to do if a recording is accidentally leaked.

#### 6.4 Liability & Insurance

- **Liability insurance:** Check if your studio's insurance covers AI-assisted lesson feedback. If not, consider adding it.
- **Indemnity:** If you use third-party services (Whisper, Deepgram, Buzz relay hosted by a vendor), ensure their terms include indemnification.
- **Incident response plan:** In case of a data breach, have a plan to notify users, regulators, and press.

#### 6.5 Explicit Studio Policy

In your studio terms of service or studio handbook, add:

> **Recording & AI Feedback**  
> Lessons may be recorded and transcribed to generate personalized feedback via AI. Recording is voluntary; students and parents must explicitly consent. Recordings are retained for [X time]; transcripts for [Y time]. Students can request deletion anytime. Teachers and students can access their own recordings and feedback; recordings are not shared externally without explicit consent.

---

## 7. Integration & Deployment Checklist

### Pre-Phase-1

- [ ] Security audit: hash/salt-check stored Nostr private keys; encrypt in database or secrets manager.
- [ ] TLS cert: acquire cert for relay domain (e.g., `relay.your-domain.music`); autorenew.
- [ ] Deployment environment: decide on Render container, separate VPS, or Railway.
- [ ] Testing setup: dev Buzz relay for integration tests; prod relay for real users.

### Phase 1 (Channels)

- [ ] Buzz relay deployed and accessible.
- [ ] User signup generates Nostr keypair.
- [ ] Phoenix endpoints create/manage channels.
- [ ] UI (embed Buzz web client or build LiveView browser).
- [ ] End-to-end test: teacher posts message → student sees it.

### Phase 2 (Agent Lesson Plans)

- [ ] Agent code written & tested (prompt engineering, orchestration).
- [ ] Agent keypair generated & stored.
- [ ] Workflow: teacher approves lesson → agent joins channel → posts plan.
- [ ] Monitoring: track agent latency, error rates, plan quality.

### Phase 3 (Capture & Transcription)

- [ ] Consent form implemented & tested with legal review.
- [ ] Recording method chosen (external service, sidecar, or student upload).
- [ ] Transcription service integrated & tested.
- [ ] Retention & deletion automation in place.
- [ ] Audit logging active.
- [ ] End-to-end test: record lesson → transcribe → agent generates feedback → appears in channel.

---

## 8. Sources & Verification

**All facts verified against:**

1. **Buzz Repository:** https://github.com/block/buzz
   - README: platform description, key features, deployment options
   - ARCHITECTURE.md: authentication flows, API endpoints, Nostr event signing, storage architecture
   - .env.example: complete list of configuration variables with descriptions
   - docs/: agent identity model, multi-tenant architecture, deployment specifics
   - LICENSE: Apache 2.0 (Block, Inc., 2026)

2. **Nostr Protocol (NIP references):**
   - NIP-01: Event format and relay protocol
   - NIP-42: WebSocket authentication
   - NIP-98: HTTP authentication

3. **Buzz Deployment & Operations:**
   - Docker Compose bundle: `deploy/compose/` directory
   - Railway one-click deployment (available on main README)
   - Agent Communication Protocol (ACP): used for agent integration

4. **Key Finding: Huddle Recording**
   - Repository status as of 2026-09-04: "Huddle lifecycle events" marked as "being wired up" (🚧).
   - Voice/huddles exist but recording + transcription are **not built in**; requires external service.

---

## 9. Open Questions & Next Steps

1. **Huddle maturity:** Verify huddle stability & recording timeline with Buzz maintainers before Phase 3.
2. **Elixir/Nostr integration:** Identify Elixir crypto libraries for Schnorr signing; test signing flow with real relay.
3. **Transcription service:** Evaluate Whisper (self-hosted vs. API), LiveKit recording, or Deepgram for cost & quality.
4. **Agent model:** Decide on LLM provider (Claude via Anthropic, GPT via OpenAI, or local); cost & latency implications for per-lesson feedback.
5. **Legal review:** Have music studio counsel review consent forms, retention policy, and data handling for your jurisdiction(s).
6. **Parental consent:** If students are minors, clarify mechanics of guardian consent (wet signature, in-app form, email confirmation).

---

## 10. Success Metrics

When each phase ships, measure:

**Phase 1:** Channel adoption (% of teachers using channels), message volume, attachment uploads.  
**Phase 2:** Agent response latency, feedback approval rate (% teacher-approved before student sees), lesson plan quality (qualitative student feedback).  
**Phase 3:** Transcription accuracy, end-to-end latency (lesson → recording → transcription → feedback), consent rate (% of sessions with recording consent), data retention compliance.

---

## Summary

**Buzz is a well-suited foundation** for studio collaboration, agent-assisted lesson planning, and eventual session capture. Its Nostr-based architecture and cryptographic audit trail align with the transparency and trust needs of music education.

The main **integration work** is not Buzz-specific—it's gluing Phoenix to Nostr keypair signing, deploying a self-hosted relay, and building the transcription & agent orchestration pipeline. **Recording and transcription are not built into Buzz** and require external services; plan Phase 3 carefully and prioritize consent/privacy from day one.

Start with Phase 1 (channels) to prove the channel collaboration model; Phase 2 (agents) to validate the feedback loop; Phase 3 (capture) only after legal + consent infrastructure is solid.
