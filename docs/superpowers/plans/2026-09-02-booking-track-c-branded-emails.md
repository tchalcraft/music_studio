# Track C — Branded Visitor Emails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the visitor-facing booking emails (confirmation, plus new cancellation and reschedule emails) a stylized, on-brand HTML body that matches the website, with website + social links and an "Add to Google Calendar" link — while keeping a plain-text part and the `.ics` attachment. The studio's own notification email stays plain text.

**Architecture:** A new pure `MusicStudio.Scheduling.EmailTemplate` renders the branded HTML shell (table layout, all CSS inlined, brand hex hardcoded with a sync comment) and a matching plain-text body. `Scheduling.Notifier` composes visitor emails as multipart (html + text) using it, adds cancellation/reschedule builders, and a small pure Google-Calendar-URL helper. `Scheduling` calls the new notifier functions as best-effort side effects on cancel/reschedule.

**Tech Stack:** Elixir 1.18 / Phoenix ~> 1.7 / LiveView ~> 1.2, Swoosh (`Swoosh.Adapters.Test` in test, `.Local` in dev, Resend in prod).

**Feature plan:** `~/.claude/plans/i-want-to-change-goofy-honey.md` (Track C)

## Global Constraints

- Work in the **`music_studio.scheduling`** worktree; all paths relative to it. jj+git colocated — commit with `git commit`.
- **`mix precommit` stays green**: `compile --warnings-as-errors --force`, `skills.check`, `deps.unlock --unused`, `format`, `gettext.extract --check-up-to-date`, `credo --strict`, `sobelow`, `test`.
- **Never hard-code addresses or real handles.** Website/social URLs come from config (`config/config.exs` defaults, prod from env in `config/runtime.exs`); social defaults are `nil` and render only when set.
- **Brand hex lives in the template** (email can't `@import`), each with a `# keep in sync with assets/css/app.css` comment. Values: accent `#3e63dd` / hover `#3358d4`, page bg `#f4f4f7`, panel `#ffffff`, border `#e0e1e6`, text `#1c2024`, muted `#60646c`. Wordmark is the text "Tristan" (Space Grotesk degrading to system) — **not** the repo's placeholder Phoenix logo.
- Email fonts degrade: `-apple-system, "Inter", system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif` (clients ignore web fonts).
- Scope is Track C only — no step-bar, no recurring.

---

### Task 1: Config for website + social links

**Files:**
- Modify: `config/config.exs`
- Modify: `config/runtime.exs`
- Modify: `config/dev.secret.example.exs`
- Test: `test/music_studio/scheduling/email_links_test.exs`

**Interfaces:**
- Produces config under `:music_studio, MusicStudio.Scheduling`: `website_url` (string | nil), `social` (keyword list `[instagram: url|nil, facebook: url|nil, youtube: url|nil]`).

- [ ] **Step 1: Write the failing test**

```elixir
# test/music_studio/scheduling/email_links_test.exs
defmodule MusicStudio.Scheduling.EmailLinksTest do
  use ExUnit.Case, async: true

  test "scheduling config exposes website_url and a social keyword list" do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling)
    assert Keyword.has_key?(cfg, :website_url)
    assert is_list(cfg[:social])
    assert Keyword.has_key?(cfg[:social], :instagram)
    assert Keyword.has_key?(cfg[:social], :facebook)
    assert Keyword.has_key?(cfg[:social], :youtube)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/email_links_test.exs`
Expected: FAIL — `:website_url` / `:social` keys absent.

- [ ] **Step 3: Add the config defaults**

In `config/config.exs`, inside the existing `config :music_studio, MusicStudio.Scheduling,` block (the one with `studio_timezone:` etc.), add these keys (before the closing of that keyword list):

```elixir
  website_url: nil,
  social: [instagram: nil, facebook: nil, youtube: nil],
```

- [ ] **Step 4: Read them from env in prod**

In `config/runtime.exs`, inside the `if config_env() == :prod do` block where `config :music_studio, MusicStudio.Scheduling,` is already set (the Google/notify block), add these keys to that same keyword list:

```elixir
    website_url: System.get_env("WEBSITE_URL"),
    social: [
      instagram: System.get_env("SOCIAL_INSTAGRAM_URL"),
      facebook: System.get_env("SOCIAL_FACEBOOK_URL"),
      youtube: System.get_env("SOCIAL_YOUTUBE_URL")
    ],
```

- [ ] **Step 5: Document local overrides**

In `config/dev.secret.example.exs`, append to the commented Scheduling block:

```elixir
# Booking email footer links (optional; only set ones render):
#   website_url: "https://your-studio-site.example",
#   social: [instagram: "https://instagram.com/…", facebook: nil, youtube: nil]
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/email_links_test.exs`
Expected: PASS (1 test).

- [ ] **Step 7: Commit**

```bash
git add config/config.exs config/runtime.exs config/dev.secret.example.exs test/music_studio/scheduling/email_links_test.exs
git commit -m "Add website + social link config for booking emails"
```

---

### Task 2: `EmailTemplate` — branded HTML + text renderer + Google Calendar link

**Files:**
- Create: `lib/music_studio/scheduling/email_template.ex`
- Test: `test/music_studio/scheduling/email_template_test.exs`

**Interfaces:**
- Produces `EmailTemplate.html(opts) :: binary()` and `EmailTemplate.text(opts) :: binary()`, where `opts` is a keyword list: `:title` (string), `:greeting` (string), `:paragraphs` (list of strings), `:details` (list of `{label, value}`), `:cta` (`%{label: String.t(), url: String.t()}` | nil).
- Produces `EmailTemplate.google_calendar_url(%{title, details, location, starts_at, ends_at}) :: binary()` — a pure `calendar.google.com/render` TEMPLATE URL (UTC stamps).
- Produces `EmailTemplate.footer_links() :: [{label :: String.t(), url :: String.t()}]` — website + only non-nil socials, from config.

- [ ] **Step 1: Write the failing tests**

```elixir
# test/music_studio/scheduling/email_template_test.exs
defmodule MusicStudio.Scheduling.EmailTemplateTest do
  use ExUnit.Case, async: false

  alias MusicStudio.Scheduling.EmailTemplate

  setup do
    prev = Application.get_env(:music_studio, MusicStudio.Scheduling)
    on_exit(fn -> Application.put_env(:music_studio, MusicStudio.Scheduling, prev) end)

    Application.put_env(
      :music_studio,
      MusicStudio.Scheduling,
      Keyword.merge(prev,
        website_url: "https://studio.example",
        social: [instagram: "https://instagram.com/tristan", facebook: nil, youtube: nil]
      )
    )
  end

  defp opts do
    [
      title: "You're booked!",
      greeting: "Hi Sam,",
      paragraphs: ["Your 60-minute piano lesson is confirmed."],
      details: [{"When", "Thursday September 10, 4:00 PM PDT"}, {"Where", "Studio"}],
      cta: %{label: "Manage your booking", url: "https://studio.example/book/manage/tok"}
    ]
  end

  test "html carries the wordmark, title, details, CTA and only configured links" do
    html = EmailTemplate.html(opts())
    assert html =~ "Tristan"
    assert html =~ "You&#39;re booked!" or html =~ "You're booked!"
    assert html =~ "Thursday September 10, 4:00 PM PDT"
    assert html =~ "Manage your booking"
    assert html =~ "https://studio.example/book/manage/tok"
    assert html =~ "https://instagram.com/tristan"
    refute html =~ "facebook.com"
    refute html =~ "youtube.com"
    # inlined styles, no external stylesheet
    assert html =~ "style="
    refute html =~ "<link"
  end

  test "text renderer produces a plain-text counterpart" do
    text = EmailTemplate.text(opts())
    assert text =~ "Hi Sam,"
    assert text =~ "When: Thursday September 10, 4:00 PM PDT"
    assert text =~ "Manage your booking: https://studio.example/book/manage/tok"
  end

  test "google_calendar_url builds a TEMPLATE render URL with UTC stamps" do
    url =
      EmailTemplate.google_calendar_url(%{
        title: "Piano lesson",
        details: "See you then",
        location: "Studio",
        starts_at: DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC"),
        ends_at: DateTime.new!(~D[2026-09-10], ~T[23:00:00], "Etc/UTC")
      })

    assert url =~ "https://calendar.google.com/calendar/render?action=TEMPLATE"
    assert url =~ "dates=20260910T220000Z%2F20260910T230000Z"
    assert url =~ "text=Piano+lesson" or url =~ "text=Piano%20lesson"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/music_studio/scheduling/email_template_test.exs`
Expected: FAIL — `EmailTemplate` undefined.

- [ ] **Step 3: Implement `EmailTemplate`**

```elixir
# lib/music_studio/scheduling/email_template.ex
defmodule MusicStudio.Scheduling.EmailTemplate do
  @moduledoc """
  Renders branded HTML (and matching plain-text) bodies for visitor-facing booking emails.
  Table-based layout with all CSS inlined for broad email-client support. Leads with a
  typographic "Tristan" wordmark (the app has no real logo yet). Brand colors are hardcoded
  here because email cannot `@import` — keep them in sync with assets/css/app.css.
  """

  # keep in sync with assets/css/app.css (Modern Minimal tokens)
  @accent "#3e63dd"
  @page_bg "#f4f4f7"
  @panel "#ffffff"
  @border "#e0e1e6"
  @text "#1c2024"
  @muted "#60646c"
  @font ~s(-apple-system, "Inter", system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif)

  @spec html(keyword()) :: binary()
  def html(opts) do
    title = Keyword.fetch!(opts, :title)
    greeting = Keyword.get(opts, :greeting, "")
    paragraphs = Keyword.get(opts, :paragraphs, [])
    details = Keyword.get(opts, :details, [])
    cta = Keyword.get(opts, :cta)

    """
    <!doctype html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
    <body style="margin:0;padding:0;background:#{@page_bg};">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@page_bg};padding:24px 0;">
        <tr><td align="center">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;background:#{@panel};border:1px solid #{@border};border-radius:12px;overflow:hidden;font-family:#{@font};">
            <tr><td style="padding:28px 32px 8px 32px;">
              <div style="font-size:22px;font-weight:700;letter-spacing:-0.02em;color:#{@text};font-family:#{@font};">Tristan</div>
              <div style="font-size:13px;color:#{@muted};">Music lessons for every age and stage</div>
            </td></tr>
            <tr><td style="padding:12px 32px 0 32px;">
              <h1 style="margin:0;font-size:20px;color:#{@text};font-weight:700;">#{h(title)}</h1>
            </td></tr>
            <tr><td style="padding:12px 32px 0 32px;color:#{@text};font-size:15px;line-height:1.55;">
              #{if greeting != "", do: "<p style=\"margin:0 0 12px 0;\">#{h(greeting)}</p>", else: ""}
              #{Enum.map_join(paragraphs, "\n", fn p -> "<p style=\"margin:0 0 12px 0;\">#{h(p)}</p>" end)}
            </td></tr>
            #{details_block(details)}
            #{cta_block(cta)}
            #{footer_block()}
          </table>
        </td></tr>
      </table>
    </body></html>
    """
  end

  @spec text(keyword()) :: binary()
  def text(opts) do
    greeting = Keyword.get(opts, :greeting, "")
    paragraphs = Keyword.get(opts, :paragraphs, [])
    details = Keyword.get(opts, :details, [])
    cta = Keyword.get(opts, :cta)

    detail_lines = Enum.map_join(details, "\n", fn {k, v} -> "#{k}: #{v}" end)
    cta_line = if cta, do: "\n#{cta.label}: #{cta.url}", else: ""
    link_lines = Enum.map_join(footer_links(), "\n", fn {label, url} -> "#{label}: #{url}" end)

    [
      greeting,
      Enum.join(paragraphs, "\n\n"),
      detail_lines,
      cta_line,
      "\n— Tristan · Music lessons in the Greater Vancouver area",
      link_lines
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  @spec google_calendar_url(map()) :: binary()
  def google_calendar_url(%{title: title, details: details, location: location, starts_at: s, ends_at: e}) do
    query =
      URI.encode_query(%{
        "action" => "TEMPLATE",
        "text" => title,
        "details" => details,
        "location" => location,
        "dates" => "#{stamp(s)}/#{stamp(e)}"
      })

    "https://calendar.google.com/calendar/render?" <> query
  end

  @spec footer_links() :: [{String.t(), String.t()}]
  def footer_links do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling, [])
    social = Keyword.get(cfg, :social, [])

    [
      {"Website", Keyword.get(cfg, :website_url)},
      {"Instagram", social[:instagram]},
      {"Facebook", social[:facebook]},
      {"YouTube", social[:youtube]}
    ]
    |> Enum.filter(fn {_label, url} -> is_binary(url) and url != "" end)
  end

  defp details_block([]), do: ""

  defp details_block(details) do
    rows =
      Enum.map_join(details, "\n", fn {label, value} ->
        """
        <tr>
          <td style="padding:4px 0;color:#{@muted};font-size:13px;width:110px;">#{h(label)}</td>
          <td style="padding:4px 0;color:#{@text};font-size:14px;font-weight:600;">#{h(value)}</td>
        </tr>
        """
      end)

    """
    <tr><td style="padding:16px 32px 0 32px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@page_bg};border:1px solid #{@border};border-radius:8px;padding:12px 16px;">
        #{rows}
      </table>
    </td></tr>
    """
  end

  defp cta_block(nil), do: ""

  defp cta_block(%{label: label, url: url}) do
    """
    <tr><td style="padding:20px 32px 4px 32px;">
      <a href="#{h(url)}" style="display:inline-block;background:#{@accent};color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;padding:12px 20px;border-radius:8px;font-family:#{@font};">#{h(label)}</a>
    </td></tr>
    """
  end

  defp footer_block do
    links =
      footer_links()
      |> Enum.map_join(" &nbsp;·&nbsp; ", fn {label, url} ->
        "<a href=\"#{h(url)}\" style=\"color:#{@accent};text-decoration:none;\">#{label}</a>"
      end)

    year = Date.utc_today().year

    """
    <tr><td style="padding:24px 32px 28px 32px;border-top:1px solid #{@border};margin-top:16px;">
      #{if links != "", do: "<div style=\"font-size:13px;margin-bottom:8px;\">#{links}</div>", else: ""}
      <div style="font-size:12px;color:#{@muted};">© #{year} Tristan · Music lessons in the Greater Vancouver area.</div>
    </td></tr>
    """
  end

  defp stamp(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  # Minimal HTML escaping for interpolated text.
  defp h(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/music_studio/scheduling/email_template_test.exs`
Expected: PASS (3 tests). (Note the CTA/title assertions allow the escaped apostrophe `You&#39;re`.)

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling/email_template.ex test/music_studio/scheduling/email_template_test.exs
git commit -m "Add branded EmailTemplate (HTML + text) and Google Calendar link helper"
```

---

### Task 3: Confirmation email gains an HTML body

**Files:**
- Modify: `lib/music_studio/scheduling/notifier.ex`
- Modify: `test/music_studio/scheduling/notifier_test.exs`

**Interfaces:**
- Consumes: `EmailTemplate.html/1`, `EmailTemplate.text/1`, `EmailTemplate.google_calendar_url/1`.
- `deliver_booking_emails/1` unchanged signature; the visitor confirmation now sets both `html_body` and `text_body` (multipart) and keeps the `.ics` attachment. The studio notification stays plain text.

- [ ] **Step 1: Update the test to assert multipart**

Replace the body of `test/music_studio/scheduling/notifier_test.exs` with:

```elixir
defmodule MusicStudio.Scheduling.NotifierTest do
  use ExUnit.Case, async: true
  import Swoosh.TestAssertions

  alias MusicStudio.Scheduling.Notifier

  defp details do
    %{
      visitor_name: "Sam",
      visitor_email: "sam@example.com",
      instrument: "piano",
      starts_at: DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC"),
      ends_at: DateTime.new!(~D[2026-09-10], ~T[23:00:00], "Etc/UTC"),
      duration_minutes: 60,
      manage_url: "http://localhost:4000/book/manage/tok",
      uid: "uid-1",
      organizer_email: "tristan@example.com",
      timezone: "America/Vancouver"
    }
  end

  test "visitor confirmation is multipart (html + text) with the wordmark, the time and an .ics" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.to == [{"Sam", "sam@example.com"}] and
        is_binary(email.html_body) and email.html_body =~ "Tristan" and
        is_binary(email.text_body) and
        Enum.any?(email.attachments, &(&1.content_type == "text/calendar"))
    end)
  end

  test "cancellation email is sent to the visitor" do
    assert {:ok, _} = Notifier.deliver_cancellation(details())
    assert_email_sent(fn e -> e.to == [{"Sam", "sam@example.com"}] and e.subject =~ "cancel" end)
  end

  test "reschedule email is sent to the visitor" do
    assert {:ok, _} = Notifier.deliver_reschedule(details())
    assert_email_sent(fn e -> e.to == [{"Sam", "sam@example.com"}] and e.subject =~ "moved" end)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling/notifier_test.exs`
Expected: FAIL — no `html_body`, and `deliver_cancellation/1`/`deliver_reschedule/1` undefined.

- [ ] **Step 3: Rework `Notifier`**

Rewrite `lib/music_studio/scheduling/notifier.ex` as:

```elixir
defmodule MusicStudio.Scheduling.Notifier do
  @moduledoc """
  Sends booking emails via the configured Swoosh adapter (Resend in prod). Visitor-facing
  emails (confirmation, cancellation, reschedule) are branded multipart HTML+text via
  `EmailTemplate`, with an `.ics` attachment on the confirmation. The studio notification
  stays plain text. Addresses come from `config :music_studio, MusicStudio.Scheduling`.
  """
  import Swoosh.Email

  alias MusicStudio.Mailer
  alias MusicStudio.Scheduling.{EmailTemplate, ICS}

  @spec deliver_booking_emails(map()) :: {:ok, map()} | {:error, term()}
  def deliver_booking_emails(details) do
    from_addr = cfg(:notify_from)
    to_addr = cfg(:notify_to)
    when_str = local_string(details.starts_at, details.timezone)
    ics = ICS.build(ics_attrs(details, from_addr))

    gcal =
      EmailTemplate.google_calendar_url(%{
        title: "#{String.capitalize(details.instrument)} lesson",
        details: "#{details.duration_minutes}-minute #{details.instrument} lesson. Manage: #{details.manage_url}",
        location: "Studio",
        starts_at: details.starts_at,
        ends_at: details.ends_at
      })

    body_opts = [
      title: "You're booked!",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: [
        "Your #{details.duration_minutes}-minute #{details.instrument} lesson is confirmed. The attached calendar file (lesson.ics) can be added to your calendar, or use the button below for Google Calendar.",
        "Need to change it? Use the link below."
      ],
      details: [{"When", when_str}, {"Where", "Studio"}],
      cta: %{label: "Add to Google Calendar", url: gcal}
    ]

    extra = [{"Manage your booking", details.manage_url}]

    confirmation =
      new()
      |> to({details.visitor_name, details.visitor_email})
      |> from({"Tristan Music", from_addr})
      |> subject("Your #{details.instrument} lesson is booked — #{when_str}")
      |> html_body(EmailTemplate.html(body_opts))
      |> text_body(EmailTemplate.text(body_opts ++ [details: body_opts[:details] ++ extra]))
      |> attachment(
        Swoosh.Attachment.new({:data, ics},
          filename: "lesson.ics",
          content_type: "text/calendar",
          type: :attachment
        )
      )

    notification =
      new()
      |> to(to_addr)
      |> from({"Music Studio Website", from_addr})
      |> reply_to(details.visitor_email)
      |> subject("New booking: #{details.instrument} — #{when_str}")
      |> text_body(notification_body(details, when_str))

    with {:ok, _} <- Mailer.deliver(confirmation),
         {:ok, _} <- Mailer.deliver(notification) do
      {:ok, %{confirmation: confirmation, notification: notification}}
    end
  end

  @spec deliver_cancellation(map()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_cancellation(details) do
    when_str = local_string(details.starts_at, details.timezone)

    opts = [
      title: "Your lesson is cancelled",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: ["Your #{details.instrument} lesson on #{when_str} has been cancelled. Hope to see you again soon — you can book any time."],
      details: [{"Was", when_str}],
      cta: nil
    ]

    deliver_visitor(details, "Your #{details.instrument} lesson was cancelled", opts)
  end

  @spec deliver_reschedule(map()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reschedule(details) do
    when_str = local_string(details.starts_at, details.timezone)

    opts = [
      title: "Your lesson moved",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: ["Your #{details.instrument} lesson has been moved. Here are the new details:"],
      details: [{"New time", when_str}, {"Where", "Studio"}],
      cta: %{label: "Manage your booking", url: details.manage_url}
    ]

    deliver_visitor(details, "Your #{details.instrument} lesson moved to #{when_str}", opts)
  end

  defp deliver_visitor(details, subject, opts) do
    email =
      new()
      |> to({details.visitor_name, details.visitor_email})
      |> from({"Tristan Music", cfg(:notify_from)})
      |> subject(subject)
      |> html_body(EmailTemplate.html(opts))
      |> text_body(EmailTemplate.text(opts))

    with {:ok, _} <- Mailer.deliver(email), do: {:ok, email}
  end

  defp ics_attrs(d, organizer_email) do
    %{
      uid: d.uid,
      summary: "#{String.capitalize(d.instrument)} lesson — #{d.visitor_name}",
      description: "#{d.duration_minutes}-minute #{d.instrument} lesson. Manage: #{d.manage_url}",
      location: "Studio",
      starts_at: d.starts_at,
      ends_at: d.ends_at,
      organizer_email: d.organizer_email || organizer_email,
      attendee_email: d.visitor_email,
      now: DateTime.utc_now()
    }
  end

  defp notification_body(d, when_str) do
    """
    New online booking:

    Name:       #{d.visitor_name}
    Email:      #{d.visitor_email}
    Instrument: #{String.capitalize(d.instrument)}
    When:       #{when_str} (#{d.duration_minutes} min)
    """
  end

  defp local_string(dt, tz) do
    dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%A %B %-d, %Y at %-I:%M %p %Z")
  end

  defp cfg(key),
    do: Keyword.fetch!(Application.get_env(:music_studio, MusicStudio.Scheduling), key)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/music_studio/scheduling/notifier_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/music_studio/scheduling/notifier.ex test/music_studio/scheduling/notifier_test.exs
git commit -m "Brand the visitor confirmation and add cancellation/reschedule emails"
```

---

### Task 4: Wire cancellation/reschedule emails into the Scheduling context

**Files:**
- Modify: `lib/music_studio/scheduling.ex`
- Test: `test/music_studio/scheduling_test.exs`

**Interfaces:**
- Consumes: `Notifier.deliver_cancellation/1`, `Notifier.deliver_reschedule/1`.
- `cancel_booking/1` and `reschedule_booking/2` now send the visitor email as a best-effort side effect. To build the email `details`, the lesson is loaded with `:student`, `:instrument`, `:teacher` preloaded.

- [ ] **Step 1: Write the failing test**

Add to `test/music_studio/scheduling_test.exs` (inside the existing module, which already sets up teacher/piano/offering/credentials and the `Req.Test` stub):

```elixir
  test "cancelling a booking emails the visitor" do
    Req.Test.stub(GoogleAuth, fn conn -> Req.Test.json(conn, %{"id" => "evt-1"}) end)
    import Swoosh.TestAssertions

    starts = DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC")

    {:ok, lesson} =
      Scheduling.create_booking(%{
        instrument_slug: "piano",
        duration_minutes: 60,
        starts_at: starts,
        name: "Sam Lee",
        email: "sam@example.com",
        phone: nil
      })

    assert {:ok, _} = Scheduling.cancel_booking(lesson.booking_token)
    assert_email_sent(fn e -> e.to == [{"Sam Lee", "sam@example.com"}] and e.subject =~ "cancel" end)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/music_studio/scheduling_test.exs -k "cancelling a booking emails"`
Expected: FAIL — no cancellation email sent.

- [ ] **Step 3: Preload associations on token lookup**

In `lib/music_studio/scheduling.ex`, change `get_lesson_by_token/1` to preload what the emails need:

```elixir
  @spec get_lesson_by_token(String.t()) :: Lesson.t() | nil
  def get_lesson_by_token(token) do
    Repo.one(
      from l in Lesson,
        where: l.booking_token == ^token,
        preload: [:student, :instrument, :teacher]
    )
  end
```

(`from`/`Lesson` are already imported/aliased in this module.)

- [ ] **Step 4: Build email details and send on cancel/reschedule**

Add a private helper and calls. In `do_cancel/1`, after the successful `Repo.update`, before returning, add the email side effect; in `do_reschedule/2`, after the successful update. Insert this helper near the other private helpers:

```elixir
  defp lesson_email_details(lesson) do
    %{
      visitor_name: full_name(lesson.student),
      visitor_email: lesson.student.email,
      instrument: (lesson.instrument && String.downcase(lesson.instrument.name)) || "music",
      starts_at: lesson.scheduled_start,
      ends_at: lesson.scheduled_end,
      duration_minutes: lesson.duration_minutes,
      manage_url: MusicStudioWeb.Endpoint.url() <> "/book/manage/" <> lesson.booking_token,
      uid: lesson.id,
      organizer_email: lesson.teacher && lesson.teacher.email,
      timezone: cfg(:studio_timezone)
    }
  end

  defp full_name(%{first_name: f, last_name: nil}), do: f
  defp full_name(%{first_name: f, last_name: l}), do: String.trim("#{f} #{l}")
```

In `do_cancel/1`, change the tail so it emails after cancelling (the lesson here is the preloaded one from `get_lesson_by_token`):

```elixir
  defp do_cancel(lesson) do
    {:ok, cancelled} =
      lesson
      |> Lesson.changeset(%{status: :cancelled, deleted_at: DateTime.utc_now()})
      |> Repo.update()

    delete_event(cancelled)
    side_effect(fn -> Notifier.deliver_cancellation(lesson_email_details(lesson)) end)
    {:ok, cancelled}
  end
```

In `do_reschedule/2`, after `{:ok, updated}`:

```elixir
      {:ok, updated} ->
        update_event(updated, new_starts_at, new_end)
        side_effect(fn -> Notifier.deliver_reschedule(lesson_email_details(%{lesson | scheduled_start: updated.scheduled_start, scheduled_end: updated.scheduled_end})) end)
        {:ok, updated}
```

(The `%{lesson | …}` keeps the preloaded `:student`/`:instrument`/`:teacher` while using the new times; `updated` from `Repo.update` is not preloaded.)

Ensure `alias MusicStudio.Scheduling.{Availability, Credentials, GoogleCalendar, Notifier}` already includes `Notifier` (it does).

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/music_studio/scheduling_test.exs`
Expected: PASS (all, including the new cancellation-email test).

- [ ] **Step 6: Commit**

```bash
git add lib/music_studio/scheduling.ex test/music_studio/scheduling_test.exs
git commit -m "Send visitor emails on cancel/reschedule"
```

---

### Task 5: Full gate + live check + docs note

**Files:** none (verification) — plus a note to carry to the project `lessons.md`.

- [ ] **Step 1: Run the full precommit gate**

Run: `mix precommit`
Expected: exits 0. Fix any `format`/`credo --strict`/`sobelow` findings (e.g. keep the big HTML heredoc readable; if credo flags the template function length, extract the header/footer into small private functions — already partially done).

- [ ] **Step 2: Live check (dev)**

Use the session's local-dev harness (npm blocked → binaries copied): `cp ../music_studio/_build/esbuild-darwin-arm64 _build/`, `cp ../music_studio/_build/tailwind-macos-arm64-4.3.0 _build/`, recreate the git-ignored `config/dev.secret.exs` Google stub + a `scheduling_credentials` row, then `env -u DATABASE_URL PORT=4010 mix phx.server`. Book a lesson at `http://localhost:4010/book`, open `http://localhost:4010/dev/mailbox`, and confirm the confirmation renders as branded HTML (wordmark, indigo CTA, details card, footer with only-configured links) with a plain-text alternative and the `lesson.ics` attachment. Cancel via the manage link and confirm the cancellation email arrives.

- [ ] **Step 3: Follow-up note (not an edit here)**

Record in the project `lessons.md` (parent Tristan repo): "Booking email brand hex is duplicated in `lib/music_studio/scheduling/email_template.ex` (email can't import CSS) — keep it in sync with `assets/css/app.css` when the palette changes." (Left for the human/step that has access to the Tristan repo; this worktree session is scoped to the app.)

## Self-Review

**Spec coverage (Track C):** branded HTML shell with wordmark (Task 2), multipart html+text on the confirmation (Task 3), cancellation + reschedule emails added and wired (Tasks 3–4), `.ics` kept + Google Calendar link (Tasks 2–3), config-driven website/social links rendered only when set (Tasks 1–2), studio notification stays plain text (Task 3), sync-comment on brand hex + lessons.md note (Tasks 2, 5). Coupon intentionally absent.

**Placeholders:** none — every code step has complete code.

**Type consistency:** `EmailTemplate.html/1`/`text/1` take the same keyword `opts`; `footer_links/0` and `google_calendar_url/1` signatures match their call sites in `Notifier`; `lesson_email_details/1` produces the same `details` map shape the `Notifier` functions consume.

## Execution Handoff

Implement with superpowers:subagent-driven-development (fresh subagent per task + review) or executing-plans (inline with checkpoints).
