# User Journey: Tristan Chalcraft Music Studio

**Overview:** Two distinct user personas navigate the music_studio platform. This document maps their goals, touchpoints, system behavior, and UX friction points.

---

## Persona A: Prospective Student / Parent (New Visitor)

**Goal:** Discover whether voice, piano, or guitar lessons might be a fit, and either inquire or book immediately.

### Journey Stages

#### Stage 1: Discover
| Aspect | Detail |
|--------|--------|
| **User goal** | Find music lessons in the area; evaluate fit |
| **Discovery path** | SEO (thin), referral, word-of-mouth |
| **System state** | Public home page visible to all |
| **What system does** | N/A — no system touchpoint yet |
| **Gaps & opportunities** | **SEO is bare-bones:** no schema.org structured data, no sitemap, no OpenGraph meta tags for social sharing. Referral and repeat-visitor friction from unclear value prop |

---

#### Stage 2: Land on `/` (Home Page)
| Aspect | Detail |
|--------|--------|
| **User goal** | Quickly assess: Is this the right studio? What's offered? Cost? |
| **Touchpoint** | Route: `/` (LiveView: `MusicStudioWeb.HomeLive`) |
| **What system does** | **Renders marketing page with five sections:** Hero (tagline + CTA buttons), About (teacher bio + credentials), Lessons & Rates (card grid: Voice/Piano/Guitar; pricing table: 30min/$35, 45min/$50, 60min/$70; scheduling policy), Booking teaser, Contact form. One-page scroll; no CMS yet. |
| **Code location** | `lib/music_studio_web/live/home_live.ex:1–362` |
| **Gaps & opportunities** | **Page is hand-built LiveView, not Beacon CMS.** (Beacon is live but the home page stays code for now — see runbook decision matrix.) No mobile optimization concerns visible (Tailwind is responsive, but no explicit mobile-first audit). Teacher photo is present. |

---

#### Stage 3: Explore (Read Bio / Lessons / Rates)
| Aspect | Detail |
|--------|--------|
| **User goal** | Understand Tristan's background, teaching approach, lesson fit for age/level, cost per-instrument |
| **Touchpoint** | On-page scroll (no new route) |
| **What system does** | **About section** displays: university diplomas (Capilano: Piano/Voice/Conducting; UVic: Voice), Bea Scott Scholarship (2014), City of White Rock Award (2010), professional ensemble experience. **Lessons section** has three cards (Voice/Piano/Guitar) with brief descriptions; a rates table; scheduling policy (24h cancel notice, pause up to 1 month, weekly slots held). |
| **Gaps & opportunities** | **Trial lesson** or free 15-min consult not mentioned; no age/level filter (lesson offerings list all ages/levels as welcome). Scheduling policy is clear, but no contrast for "what's unusual here" (pause feature may not jump out). |

---

#### Stage 4: Decide — **Two Coexisting Entry Paths**

##### Path A: Inquire via Contact Form
| Aspect | Detail |
|--------|--------|
| **User goal** | Ask a question before committing (specific level, age range, instrument fit, custom arrangement) |
| **Touchpoint** | Route: `/` (same page). Form at bottom: "Contact" section |
| **Form fields** | Name (required), Email (required), Instrument (required select: Voice/Piano/Guitar), Message (optional textarea with placeholder: "Who are the lessons for? What would you like to learn?") |
| **What system does** | 1. Form validated on client (required fields) and server (Leads.change_lead / Leads.create_lead). 2. On submit: `Leads.create_lead(params)` saves Lead record to DB (name, email, instrument, message, inserted_at). 3. **Best-effort async:** `Leads.Notifier.deliver_inquiry_notification(lead)` sends **text-only email** to owner (from `inquiry_to` config, default `owner@example.com`) with subject "New lesson inquiry from {name}" and body listing name, email, instrument, message. 4. Owner must reply manually (no reply-to routing, no CRM integration yet). 5. Visitor sees inline success message: "Thank you — your inquiry has been sent. I'll be in touch by email as soon as I can." Form clears. |
| **Code location** | `lib/music_studio/leads.ex:1–40`, `lib/music_studio/leads/notifier.ex:1–72`, `lib/music_studio_web/live/home_live.ex:37–52` |
| **Gaps & opportunities** | **Large friction:** No confirmation email to the visitor (only owner gets notified). No lead status tracking (inquiry vanishes from visitor's view). No CRM or auto-reply. No SMS fallback. Owner must hunt through email to follow up; no lead queue or pipeline. |

##### Path B: Self-Serve Book at `/book`
| Aspect | Detail |
|--------|--------|
| **User goal** | Book immediately without inquiry friction; see availability; confirm via email |
| **Touchpoint** | Route: `/book` (LiveView: `MusicStudioWeb.BookingLive`) |
| **Flow steps** | **4-step wizard with progress bar:** (1) Lesson — pick Instrument (Voice/Piano/Guitar button grid) + Length (30/45/60 min grid). (2) Schedule — pick Cadence (radio: "Just once" / "Weekly (school year)" / "Every other week"), then calendar grid (single) or representative week (recurring) to pick day/time slot. (3) Your details — name, email, phone. (4) Confirmed — summary; "Check your email for confirmation and calendar invite." |
| **Availability logic** | Slots computed from: studio working hours (Mon–Fri 2–9pm PT), already-booked lessons and held recurring-series slots (both from the database), lesson duration, buffer time (default 15 min), and minimum notice (default 24h). Availability is **not** read from Google Calendar — the calendar is write-only (lessons are pushed to it on booking). Single bookings look ~2 months out; recurring series run through June 30 and show conflict warnings if weeks can't fit the usual time. |
| **Booking action** | `Scheduling.create_booking` (single) or `Scheduling.create_series` (recurring): (a) Upserts Student (email as key; status: "prospective"). (b) Inserts Lesson record(s) (one per booking or multiple per series). (c) Writes Google Calendar event(s) to teacher's calendar (event title includes student name, description has contact info). (d) Sends confirmation email via `Scheduling.Notifier.deliver_booking_emails` with calendar invite (.ics file, Resend). (e) Records `lesson_booked` or `series_booked` event to Analytics. (f) Returns lesson token for manage link. |
| **Email sent** | Subject: "Lesson booking confirmation" (or "Series booked: X lessons through June 30"). Body includes: lesson time, duration, instrument, manage link (token-based, no auth). Attached: .ics file with Google event (for calendar import). |
| **Code location** | `lib/music_studio_web/live/booking_live.ex:1–685`, `lib/music_studio/scheduling.ex:253–291` (create_booking), lines 115–148 (create_series), `lib/music_studio/scheduling/notifier.ex` (email delivery) |
| **Gaps & opportunities** | **No account/login required.** Token is the only identifier, sent via email. **Parallel-path confusion:** visitors see two CTAs ("Inquire about lessons" + "Book a session") — is it OK to book without talking first? Unclear. Inquiry form is at bottom of home page, booking is linked everywhere (nav, hero CTA) — booking seems pushed more. No trial-booking or deposit flow. Calendar invite quality depends on Resend delivery; if email lands in spam, student loses the ICS. Conflict handling for recurring series is crude: "we'll follow up about alternates" but no automated rescheduling offered at book time. |

---

#### Stage 5: First Lesson
| Aspect | Detail |
|--------|--------|
| **User goal** | Show up, learn, have a good experience |
| **Touchpoint** | Physical in-person studio (or external calendar app on student's device) |
| **What system does** | Google Calendar event shows on teacher's calendar; student received .ics invite; both have the time + location ("Studio") + contact info. Lesson record in DB (`Teaching.Lesson`) has status: scheduled. On day-of, no system reminder (no SMS, no email ping). Post-lesson, no automatic follow-up prompt (no "how was it?" survey, no rebook suggestion). |
| **Gaps & opportunities** | **No pre-lesson reminder** to student (24h or 1h SMS/email). **No post-lesson flow:** no survey, no invoice generation trigger, no upsell prompt. If recurring series, no per-lesson notes or feedback capture. |

---

#### Stage 6: Follow-up / Rebook / Pay Invoice
| Aspect | Detail |
|--------|--------|
| **User goal** | Book another lesson, pay for the last one, manage future bookings |
| **Touchpoint** | Email or student initiates; routes: `/book` (rebook), `/book/manage/:token` (manage), `/invoices/:id/pay` (pay) |
| **Rebook flow** | Visit `/book` again as new user (no account login) — full wizard from scratch. Or, if they're an existing Student in DB (email match), they're de-duped but they won't know that (no UI confirmation). |
| **Manage flow** | Token link from booking email → `/book/manage/:token` (LiveView: `MusicStudioWeb.BookingManageLive`). Single lesson: button to "Cancel booking". Recurring series: list upcoming lessons with per-lesson "Skip" button, "Pause (up to a month)" button (cancels up to 4 weeks, holds time slot), "Cancel series" button. If pause/skip, no email notification to student — they just see the change when they revisit the link. |
| **Pay invoice flow** | Owner sends student a link: `/invoices/:id/pay` where id is UUIDv7. Student clicks → sees invoice amount → clicks "Pay now" → redirected to Stripe Checkout (hosted page) → pays → Stripe webhook calls `MusicStudioWeb.StripeWebhookController` to mark invoice as paid + send receipt email. Student sees success page: "Thank you — payment received. Receipt will follow by email." No in-app invoice history; student must rely on email receipts. |
| **Code location** | `lib/music_studio_web/live/booking_manage_live.ex:1–152` (manage), `lib/music_studio_web/live/invoice_pay_live.ex:1–125` (pay), `lib/music_studio/scheduling.ex:293–356` (cancel/reschedule logic) |
| **Gaps & opportunities** | **No student portal or login.** All access is token-based (emailed links). If student loses email, they lose manage link. **No invoice history.** Only way to pay is via link sent by owner; no self-service invoice list. **Recurring series pause notification:** student is not notified that their pause was applied — they discover it by revisiting manage link. **Reschedule missing in UI:** Manage link shows Skip + Pause + Cancel, but no "reschedule to another time" button (backend function exists: `Scheduling.reschedule_booking/2`, but no UI). **Pause limit (4 weeks)** is not clearly explained upfront; student might expect unlimited pause. |

---

## Persona B: Existing Student (Recurring Series Subscriber)

**Goal:** Manage booked lessons, skip/pause as needed, pay invoices, potentially rebook or add lessons.

### Journey Stages

#### Stage 1: Manage Upcoming Lessons
| Aspect | Detail |
|--------|--------|
| **User goal** | Skip a week, pause for a month, or cancel the whole series; see what's coming |
| **Touchpoint** | Route: `/book/manage/:token` (token from booking email) |
| **What system does** | **Token resolves to either Enrollment (recurring series) or Lesson (single).** For series: lists all upcoming scheduled lessons (queried from DB, filtered by enrollment_id, status=scheduled, not deleted). For each lesson, button: "Skip" (cancels that one occurrence without notifying student). Top buttons: "Pause (up to a month)" (cancels up to 4 future lessons, holds weekly time slot), "Cancel series" (marks enrollment as cancelled, cancels all future lessons). No email is sent to the student when they take these actions; they must refresh the page to confirm. |
| **Code location** | `lib/music_studio_web/live/booking_manage_live.ex:1–152` |
| **Gaps & opportunities** | **No notification of state change.** Student clicks "Skip" and sees no confirmation email; they have to revisit the page to verify. **Pause limit unclear:** says "up to a month" but the code caps at 4 weeks (hardcoded `@pause_max 4`); a 5-week pause attempt would silently cap to 4. **No reschedule UI:** if a lesson is cancelled, there's no inline "pick a new time" flow — student must go back to `/book` and rebook separately. **Series context missing:** manage page doesn't show the enrollment start/end dates, recurrence pattern (weekly vs. biweekly), or total remaining lessons. |

---

#### Stage 2: Pay an Invoice
| Aspect | Detail |
|--------|--------|
| **User goal** | Pay balance due for lessons completed |
| **Touchpoint** | Route: `/invoices/:id/pay` (link sent by owner) |
| **What system does** | **No auth required.** Invoice id is a UUIDv7 (unguessable but not secret). Display: invoice amount. Button: "Pay now". On click, creates Stripe Checkout Session (Stripe Tax is omitted — see commit 4f4caa2 decision), redirects to Stripe hosted checkout page. Student enters card, Stripe processes. On success, webhook hits `StripeWebhookController`, marks invoice as paid in DB, sends receipt email to customer. Student sees success page: "Thank you — payment received. Receipt will follow by email." No in-app invoice list; student sees only the one invoice they were sent a link to. |
| **Code location** | `lib/music_studio_web/live/invoice_pay_live.ex:1–125`, `lib/music_studio/billing/stripe.ex` (checkout session creation) |
| **Gaps & opportunities** | **No invoice discovery.** If owner forgets to send the link, student has no way to pay. **No recurring billing.** Each invoice is manual; no auto-charge or subscription. **No in-app history.** Student can't see past invoices, outstanding balance, or payment status except by looking at email. **Paid invoice state:** if student revisits the link and the invoice is already paid, they see "This invoice is paid. Thank you! Nothing more is due." but no receipt or details. |

---

#### Stage 3: Rebook / Add Lessons
| Aspect | Detail |
|--------|--------|
| **User goal** | Book more lessons (extend series or book one-offs) |
| **Touchpoint** | Route: `/book` (full wizard) |
| **What system does** | Same as Path B above. Student is treated as a new visitor (no "Welcome back" or auto-fill). Email match in the Student table means they're de-duped in the background (no duplicate records), but the UI gives no feedback. If they're a recurring subscriber, they can book an additional one-off lesson, which creates a separate Lesson record (not tied to their Enrollment). Notifications go to both contacts (teacher + student). |
| **Gaps & opportunities** | **No returning-student UX.** No "book another lesson in your usual time" quick-path. No pre-fill of email/phone. No indication that they're already a student (no "Welcome back, Alice!" or series summary). **Separate one-off lessons:** if a recurring student books a one-off, it's a separate Lesson record with its own token; not bundled with their series manage link. This can be confusing (two different manage pages). |

---

## Cross-Cutting Friction Points & UX Opportunities

### Critical Gaps
1. **Two parallel booking entry points (inquiry form vs. self-serve book).** Visitors may not know which path to take. CTA prominence slightly favors "Book a session," which may frustrate first-time visitors who want to ask questions first. Consider: consolidate to one flow, or add inline copy ("New? Ask questions below" vs. "Ready to book? Click here").

2. **No account / login.** All access is token-based (email links). Losing an email = losing manage link. No student portal or booking history. Existing students see no "my bookings" or "my lessons" page. Consider: optional account creation after booking, with token-less access to manage page and invoice history.

3. **Token-based security model scales poorly.** Tokens are sent in emails, stored in URLs, and have no expiration. If a token leaks, anyone with the link can cancel a student's lessons. Consider: add token expiration (e.g., 6 months); pin manage link to email address (confirm via magic link on revisit); add optional PIN or password.

4. **Thin SEO and discovery layer.** No structured data (schema.org), no sitemap, no OG tags for social sharing. First-time visitors from search or referral can't easily share the page. Consider: add JSON-LD LocalBusiness, event schema for lessons; generate dynamic OG images; add sitemap + robots.txt.

5. **Inquiry form → no CRM, no auto-reply.** Owner gets an email, has to reply manually. No lead tracking, no follow-up reminders, no conversion measurement. No indication to the visitor that their inquiry was received beyond a page message. Consider: add transactional email to visitor ("We received your inquiry; we'll follow up within 24 hours"), log leads in a CRM or Slack channel, measure conversion rate.

6. **Manage link notifications are silent.** Student skips a lesson or pauses the series, but sees no confirmation or undo option. Changes are permanent unless they revisit the page. Consider: send "Your lesson was skipped" email confirmation; add a 24h undo window; show "pending" state in the UI while email is being sent.

7. **Recurring series conflict handling is manual.** If a week can't fit the usual time (e.g., holiday), the booking flags it ("N week(s) need another time") and says "we'll follow up about alternates," but no automated alternative time is offered at book time or sent in follow-up. Consider: present alternatives during booking; auto-offer adjacent time slot if usual time is blocked; or allow student to skip conflicted weeks without owner intervention.

8. **No pre-lesson reminder.** Student receives the .ics file at book time, but no reminder 24h or 1h before the lesson. (Google Calendar reminders depend on the student importing the .ics and configuring their own alerts.) Consider: send SMS or email reminder 24h before, optional 1h before.

9. **No post-lesson engagement.** After the lesson, there's no follow-up: no survey, no prompt to pay, no "how did we do?" or upsell to another lesson or series. Consider: send "thanks for your lesson, here's your invoice" or "book your next lesson" email 1–2 hours post-lesson; embed short feedback form.

10. **Reschedule feature exists in code, not UI.** Backend function `Scheduling.reschedule_booking/2` is implemented, but manage page has no "reschedule" button — only Skip, Pause, Cancel. Consider: add "reschedule" button that opens a date/time picker similar to the booking flow.

### UX Opportunities (Priority Order)
| Priority | Opportunity | Effort | Impact |
|----------|-------------|--------|--------|
| P0 | Add "We received your inquiry" confirmation email to lead; log lead in Slack or CMS | Low | High — validates visitor, no lost inquiries |
| P0 | Add transactional confirmation email on manage actions (Skip/Pause/Cancel) with undo link | Medium | High — reduces second-guessing, fewer "did it work?" support calls |
| P1 | Implement student account + login (optional); persist manage link to account | High | High — reduces token-loss friction, enables invoice history |
| P1 | Streamline booking CTA: one form that asks "First time?" (inquiry track) or "Ready?" (book track) | Medium | Medium — reduces confusion, clearer flows |
| P1 | Add "Reschedule" button to manage page | Medium | Medium — key feature, currently missing in UI |
| P2 | Implement recurring email reminders (24h, 1h before lesson) | Medium | Medium — reduces no-shows |
| P2 | Add SEO scaffolding (schema.org, OG tags, sitemap, analytics) | Low | Medium — improves search visibility, social sharing |
| P2 | Show teacher calendar availability in real time during booking; reduce query latency | Medium | Low — current performance is acceptable for small studio |
| P3 | Offer automated alternate times for conflicted recurring weeks (instead of "we'll follow up") | High | Low — nice-to-have, manual follow-up works for small volume |

---

## Appendix: Routes & Key Code

| Route | LiveView / Module | File | Purpose |
|-------|-------------------|------|---------|
| `/` | `MusicStudioWeb.HomeLive` | `lib/music_studio_web/live/home_live.ex` | Marketing page + inquiry form |
| `/book` | `MusicStudioWeb.BookingLive` | `lib/music_studio_web/live/booking_live.ex` | Self-serve booking wizard (single + recurring) |
| `/book/manage/:token` | `MusicStudioWeb.BookingManageLive` | `lib/music_studio_web/live/booking_manage_live.ex` | Manage single lesson or series (skip, pause, cancel) |
| `/invoices/:id/pay` | `MusicStudioWeb.InvoicePayLive` | `lib/music_studio_web/live/invoice_pay_live.ex` | Stripe checkout for invoice payment |

| Context / Module | File | Purpose |
|------------------|------|---------|
| `MusicStudio.Leads` | `lib/music_studio/leads.ex` | Inquiry form submission + persistence |
| `MusicStudio.Leads.Notifier` | `lib/music_studio/leads/notifier.ex` | Send inquiry notification email to owner |
| `MusicStudio.Scheduling` | `lib/music_studio/scheduling.ex` | Availability computation, booking, cancellation, rescheduling, Google Calendar integration, transactional emails |
| `MusicStudio.Scheduling.Notifier` | `lib/music_studio/scheduling/notifier.ex` | Booking confirmation, cancellation, reschedule emails |
| `MusicStudio.Billing` | `lib/music_studio/billing/*.ex` | Invoice generation, Stripe Checkout sessions |

---

**Document version:** 2026-09-04  
**Status:** Complete; seeding UX roadmap and developer understanding  
**Next steps:** Prioritize opportunities above; brief design/product team on parallel-path confusion and token-based friction
