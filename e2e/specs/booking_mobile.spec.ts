// Bombadil browser property spec — booking flow at mobile viewport (`/book`).
//
// Same API caveat as booking.spec.ts: documented v0.7.x primitives, confirm/adjust on the
// first CI run. Mobile viewport configuration (e.g., Bombadil's device emulation API) should
// be confirmed in CI — if the API is not available, fallback to viewport-agnostic assertions.
// TODO: On first CI run, verify/adjust the mobile viewport setting method (device type, dimensions,
// or `state.window.innerWidth` constraints). This spec aims to guard the mobile UX (GH #8):
// that buttons are reachable, not overlapped, and the recurrence controls work on small screens.
//
// Properties that matter:
//   - the flow never crashes (same guard as desktop);
//   - it always shows recognizable booking content;
//   - tap targets (instrument, duration, cadence, slot, pattern, Continue buttons) are present,
//     clickable, and not zero-size or off-screen (minimum ~40px where feasible);
//   - the recurrence controls (cadence radio group) are always present once on the Schedule step.

import { extract, always, actions, weighted } from "@antithesishq/bombadil";

// --- Extractors ---

// Same crash detection as booking.spec.ts.
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

// Recurrence controls (cadence radio group) are present in the schedule step.
// This ensures the mobile UI exposes the once/weekly/biweekly choice.
const hasRecurrenceControls = extract((state) => {
  const cadenceRadios = state.document.querySelectorAll('input[name="cadence"]');
  return cadenceRadios.length >= 3; // once, weekly, biweekly
});

// Presence of the key tap targets, so a mobile screen with booking content is never a
// dead-end with no controls. Geometry (min ~40px tap size, on-screen, no horizontal
// overflow) is a confirm-on-CI refinement — see the TODO at the top of this file. We stick
// to querySelector here (the primitive the existing specs use) rather than computed style,
// which isn't established in the documented v0.7.x extractor context.
const tapTargetsPresent = extract((state) => {
  const selectors = [
    '[phx-click="pick_instrument"]',
    '[phx-click="pick_duration"]',
    'input[name="cadence"]',
    '[phx-click="pick_slot"]',
    '[phx-click="pick_pattern"]',
    '[phx-click="to_details"]',
    '[phx-click="back"]',
  ];
  return selectors.some((sel) => state.document.querySelector(sel) !== null);
});

// --- Properties ---

export const neverCrashes = always(() => crashed.current === false);

export const neverStuck = always(() => hasBookingContent.current === true);

// Recurrence controls must be reachable whenever the booking flow is showing content.
export const recurrenceControlsPresent = always(
  () => hasRecurrenceControls.current === true || !hasBookingContent.current,
);

// Whenever there is booking content, at least one interactive tap target is present —
// guards against a blank/dead-end mobile screen. Tighten to geometry checks on CI (TODO).
export const tapTargetsUsable = always(
  () => tapTargetsPresent.current === true || !hasBookingContent.current,
);

// --- Action generators: drive the mobile flow ---

// Pick an offered instrument button (mobile: typically first tap target, grid layout).
export const pickInstrument = actions((state) => {
  const btn = state.document.querySelector('[phx-click="pick_instrument"]');
  return btn ? [{ Click: { element: btn } }] : [];
});

// Pick a duration (length) button.
export const pickDuration = actions((state) => {
  const btn = state.document.querySelector('[phx-click="pick_duration"]');
  return btn ? [{ Click: { element: btn } }] : [];
});

// Set cadence: rotate through once → weekly → biweekly on mobile radios.
export const setCadence = weighted([
  [2, actions((state) => {
    const radio = state.document.querySelector('input[name="cadence"][value="once"]') as HTMLInputElement;
    return radio ? [{ Click: { element: radio } }] : [];
  })],
  [1, actions((state) => {
    const radio = state.document.querySelector('input[name="cadence"][value="weekly"]') as HTMLInputElement;
    return radio ? [{ Click: { element: radio } }] : [];
  })],
  [1, actions((state) => {
    const radio = state.document.querySelector('input[name="cadence"][value="biweekly"]') as HTMLInputElement;
    return radio ? [{ Click: { element: radio } }] : [];
  })],
]);

// Pick a slot (single booking) or a pattern (recurring start day/time).
export const pickSlotOrPattern = weighted([
  [3, actions((state) => {
    const slot = state.document.querySelector('[phx-click="pick_slot"]');
    return slot ? [{ Click: { element: slot } }] : [];
  })],
  [2, actions((state) => {
    const pattern = state.document.querySelector('[phx-click="pick_pattern"]');
    return pattern ? [{ Click: { element: pattern } }] : [];
  })],
]);

// Click Continue to move to details step (only available after picking a slot/pattern).
export const clickContinue = actions((state) => {
  const btn = state.document.querySelector('[phx-click="to_details"]');
  return btn ? [{ Click: { element: btn } }] : [];
});

// Click Back to return to previous step.
export const clickBack = actions((state) => {
  const btn = state.document.querySelector('[phx-click="back"]');
  return btn ? [{ Click: { element: btn } }] : [];
});

// Mobile-focused exploration: drive the flow, reset frequently, prioritize tap targets.
// The lower weight on Continue / Back encourages lingering on choice screens.
export const mobileTour = weighted([
  [3, pickInstrument],
  [3, pickDuration],
  [2, setCadence],
  [4, pickSlotOrPattern],
  [2, clickContinue],
  [1, clickBack],
]);
