// Bombadil browser property spec — booking flow (`/book`).
//
// Same API caveat as inquiry.spec.ts: documented v0.7.x primitives, confirm/adjust on the
// first CI run. The booking flow is a guided single LiveView with steps
// Lesson → Schedule → Your details → Confirmed (booking_live.ex:12).
//
// Properties that matter:
//   - the flow never crashes and is never a blank/stuck dead-end;
//   - it always presents recognizable content (a step, offered slots, or a clear
//     "no times" / error message), so a visitor is never stranded.
// The hard "no double-booking / slots within working hours" guarantees are covered more
// precisely by the Elixir StreamData + DB tests; here we guard the end-to-end UX.

import { extract, always, actions, weighted } from "@antithesishq/bombadil";

const crashed = extract((state) => {
  const doc = state.document;
  const phxError = doc.querySelector(".phx-error, .phx-client-error, .phx-server-error");
  const bodyText = (doc.body?.innerText || "").toLowerCase();
  return phxError !== null || bodyText.includes("internal server error");
});

// The page always shows *something* recognizable from the booking flow — a step label, a
// bookable slot, a "no times" message, or the confirmation. If none of these are present
// the visitor is stuck on a blank/broken page.
const hasBookingContent = extract((state) => {
  const text = state.document.body?.innerText || "";
  const stepWords = ["Lesson", "Schedule", "Your details", "Confirmed"];
  const hasStep = stepWords.some((w) => text.includes(w));
  const hasSlot = state.document.querySelector('[phx-click="pick_slot"]') !== null;
  const hasNoTimes = /no (times|slots|availability)/i.test(text);
  return hasStep || hasSlot || hasNoTimes;
});

// --- Properties ---

export const neverCrashes = always(() => crashed.current === false);

export const neverStuck = always(() => hasBookingContent.current === true);

// --- Action generators ---

// Pick an offered slot (whichever the UI is currently showing). Bombadil will explore
// choosing an instrument/length first, then slots become clickable.
export const pickSlot = actions((state) => {
  const slot = state.document.querySelector('[phx-click="pick_slot"]');
  return slot ? [{ Click: { element: slot } }] : [];
});

// Progress / back / general clicking so Bombadil walks the guided steps.
export const stepThrough = weighted([
  [4, pickSlot],
  [2, actions(() => [{ Click: { selector: 'button[phx-click="next"]' } }])],
  [1, actions(() => [{ Click: { selector: '[phx-click="back"]' } }])],
]);
