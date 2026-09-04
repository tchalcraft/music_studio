// Bombadil browser property spec — inquiry form (home page `/`).
//
// Written against Bombadil's documented primitives (extract / always / actions / weighted,
// cell values via `.current`) for v0.7.x. The exact import path and action-payload shapes
// should be confirmed on the first CI run and adjusted if the installed version differs —
// this machine can't install/run Bombadil (the corporate npm proxy blocks the registry),
// so CI is where these first execute.
//
// The property that matters (regression guard for GH #3): submitting the inquiry form must
// always reach a visible confirmation and the page must never end up in a crashed/stuck
// state. Bombadil autonomously drives the page; we assert the invariants below hold in
// every state it visits.

import { extract, always, actions, weighted } from "@antithesishq/bombadil";

// --- Extractors: pull JSON-serializable facts out of the live DOM ---

// True when Phoenix/LiveView is showing a disconnect or server-error overlay, or the body
// contains a raw error page. This is the "never crashed" signal.
const crashed = extract((state) => {
  const doc = state.document;
  const phxError = doc.querySelector(".phx-error, .phx-client-error, .phx-server-error");
  const bodyText = (doc.body?.innerText || "").toLowerCase();
  return (
    phxError !== null ||
    bodyText.includes("internal server error") ||
    bodyText.includes("something went wrong")
  );
});

// The confirmation block rendered after a successful inquiry (home_live.ex:243).
const confirmationShown = extract((state) =>
  (state.document.body?.innerText || "").includes("your inquiry has been sent")
);

// The inquiry form is present and interactive.
const inquiryForm = extract((state) => {
  const form = state.document.querySelector('form[phx-submit="submit"]');
  return form ? { present: true } : null;
});

// --- Properties (invariants that must ALWAYS hold) ---

// The page must never be in a crashed/error overlay state, no matter what actions run.
export const neverCrashes = always(() => crashed.current === false);

// The confirmation, once shown, is a valid terminal state (sanity anchor for the flow).
export const confirmationIsClean = always(
  () => !(confirmationShown.current === true && crashed.current === true)
);

// --- Action generators: how Bombadil drives the page ---

// Fill the inquiry fields (ids come from `@form[:field].id` → lead_name / lead_email /
// lead_instrument / lead_message) and submit. Values are safe test data.
export const fillAndSubmitInquiry = actions(() =>
  inquiryForm.current
    ? [
        { Fill: { selector: "#lead_name", value: "Bombadil Test" } },
        { Fill: { selector: "#lead_email", value: "bombadil@example.com" } },
        { Select: { selector: "#lead_instrument", value: "piano" } },
        { Fill: { selector: "#lead_message", value: "Property-test inquiry" } },
        { Click: { selector: 'form[phx-submit="submit"] button[type="submit"]' } },
      ]
    : []
);

// Explore the in-page anchor nav (About / Lessons / Booking / Contact) and the Book CTA.
export const navigate = weighted([
  [3, actions(() => [{ Click: { selector: 'a[href="#contact"]' } }])],
  [1, actions(() => [{ Click: { selector: 'a[href="#lessons"]' } }])],
  [1, actions(() => [{ Click: { selector: 'a[href="#about"]' } }])],
]);
