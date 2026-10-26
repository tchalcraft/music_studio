# Changelog

Notable changes to the Tristan Chalcraft Music app (`tristanchalcraftmusic.com`).

Format loosely follows [Keep a Changelog](https://keepachangelog.com/). There are no version
numbers. Each section is a **production deploy**, titled by deploy date (UTC) and the commit
Render runs. Work that's merged to `main` but not yet deployed goes under **Unreleased**.

**Keeping it current:** add a line under *Unreleased* in the same PR as the change. When you
deploy, rename *Unreleased* to `## YYYY-MM-DD — <commit>` and start a fresh *Unreleased*. GitHub
issues are `#N`, PRs are `PR #N`, and Fizzy cards are `Fizzy #N`.

## Unreleased

### Added
- This changelog.

## 2026-10-26 — `3702708` (PR #24)

### Security
- Public forms (inquiry and booking confirm) are protected against scripted abuse. Each visitor
  IP gets 5 submits per hour per form, and a Cloudflare Turnstile bot check is verified
  server-side before anything is saved or emailed. The booking email goes to any typed address,
  so these forms had worked as a spam relay. (Fizzy #39)
- The database connection now verifies Neon's TLS certificate (`verify_peer`). It used to accept
  any certificate. (Fizzy #39)
- The origin guard also covers LiveView connections, so a WebSocket opened directly against
  the Render host can't join a page. (Fizzy #38)

### Fixed
- Error messages now appear on the home and booking pages. Before, they were silently dropped,
  so visitors never saw "that time was just taken" or "please enter your name and email".

## 2026-10-22 — `a7bd57f` (PR #23)

### Security
- **Cloudflare now fronts the domain** (DNS moved from Porkbun; Porkbun is still the registrar).
  It blocks vulnerability-scanner paths (`/wp-admin`, `*.php`, `/.env`, …) at the edge and
  rate-limits `/book` and `/live`. (Fizzy #37, #38)
- Origin guard: the app rejects requests that didn't come through Cloudflare, closing the
  `*.onrender.com` back door. Enabled the same day. (Fizzy #38)
- Booking manage-link tokens are redacted from the server logs. Anyone with log access could
  otherwise have cancelled or rescheduled bookings. (Fizzy #39)
- Upgraded dependencies with security advisories: Bandit 1.13.1 (HIGH, the web server), Mint
  1.11.0, decimal 3.2.0, lazy_html 0.1.13. hackney 1.25.0 remains flagged but its advisories
  don't apply to how it's used here. A fix needs hackney 4.x, which our dependencies don't
  support yet.
- DMARC record added, so others can't easily send spoofed email from the domain.

## 2026-10-22 — `3d339c8` (PR #22)

### Security
- **`/cms` (the Beacon content admin) now requires a password.** It had been reachable by anyone,
  and its editors can run code on the server. A check of the logs and CMS data found no sign it
  was ever misused. (Fizzy #35, #36)
- Scanner probes (`/wp-admin`, `*.php`, `/.env`, …) get a bare 404 instead of reaching the CMS.

### Changed
- Render's health check moved from `/` to a lightweight `/up` that doesn't touch the database.

## 2026-09-21 — `5034c5c` (PR #21)

### Added
- Contact email in the site footer.

### Fixed
- Scheduling tests no longer break as the calendar date moves past hard-coded 2026/2027 dates.

## 2026-09-06 — `855606e` (PR #17, PR #18)

### Added
- Rescheduling a single lesson from the emailed manage page ("pick a new time"). (#15)
- Recurring lessons offer "School year" or "Pick your dates" start and end dates, capped at June 30. (#16)

### Fixed
- Booking emails and calendar invites carry the studio's name, contact address and real location,
  and distinguish single lessons from a series. They include a "Modify booking" button. (#15, #11)

## 2026-09-05 — `d4ed54f` (PR #14)

### Fixed
- Google Calendar event IDs are saved for series lessons, so cancelled lessons don't leave
  orphaned calendar events. (#5)
- The plain-text confirmation email keeps the manage link. (#6)
- "Start later" for a recurring series stops at the end of term. (#7)
- Calendar invites show the teacher's name as organizer. (#11)
- The recurring-series preview no longer freezes the page for about 14s (now about 0.3s).

### Changed
- The booking flow has an explicit **Continue** button on the lesson step and shows the chosen lesson.
- Buttons restyled, with readable hover and dark-mode states.

## 2026-09-04 — `2bdf10a` (PR #9)

### Added
- Teacher photo and instrument icons on the home page.
- SEO: page descriptions, social-sharing tags, and structured data for search engines.
- Analytics event recording for leads, lessons, series and invoices.

### Fixed
- The booking page is usable on phones: controls stack vertically and tap targets are bigger. (#8)
- Production booking showed no instruments. Each deploy now seeds the lesson catalog.
- Double-booking across a time-zone boundary, and a crash when the name was missing.

## 2026-09-03 — first production deploy

### Added
- Marketing site (hand-built home page) with lessons, rates and an inquiry form that emails the studio.
- Online booking at `/book`: single and weekly or bi-weekly lessons. Availability is the studio's
  working hours (Mon–Fri 2–9pm PT), and the database blocks double-booking. Confirmation emails
  include calendar invites.
- A manage link in each booking email to cancel, skip or pause.
- Google Calendar sync for bookings (service account).
- Pay-an-invoice checkout with Stripe (test mode).
- Beacon CMS for content pages at `/cms`.
- Hosting: Render (free tier) + Neon Postgres + Resend email; domain on Porkbun.
