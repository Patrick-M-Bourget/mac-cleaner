# Throwaway connected-flow review

Question: do FLOW-LOCK Q1–Q30 and FL01–FL14 form a clear, coherent plan/scope/Explorer journey in the existing approved visual direction?

Open `connected-flow-review.prototype.html` directly in a browser. No server, install, network assets or database. The state model and fixtures live in memory. Preview controls outside the window switch state, theme and initial/minimum dimensions; guided walkthroughs and ordinary app controls drive the same model. “Complete simulated scan” is review tooling, never production UI.

This branch preserves the prototype as a primary design source. It is deliberately not merged into the production integration branch. The integration branch keeps the confirmed decisions and a review pointer. Do not port the HTML into the native app or treat its synthetic amounts, browser geometry, grants, scan/Trash simulation or control behavior as native qualification. Actual source-pinned native checks follow implementation.

## What is illustrated

- Stable category plan before scan, useful/empty/mixed/blocked states, inline refinement, exact confirmation Cancel, explicit retry exit and new-plan boundary.
- Remembered included locations, direct access recovery, separate Forget, overlap-aware selection retention and scan status outside the origin.
- Existing-observation folder exploration, descendant search/no matches, allocated/logical evidence, distinct inspect/select/navigation, wide inspector and bounded compact inspector.
- Shared membership and ancestor reuse for Explorer/plan. Source current design palette and layout responsibilities remain fixed.
- Local-records entry is annotated with a message; actual maintenance/diagnostics and other secondary native panels are outside this focused prototype. Their caller-aware behavior remains required in #48. This is not a claim of whole-product parity.

## Rendering and interaction observations

`flow-review-captures/manifest.json` records 60 browser-rendered app-window PNGs: 14 FL states plus overlap, each Light/Dark at 1120×760 and900×640. Captures were rendered from the exact prototype hash recorded there, with no script errors, horizontal content overflow or out-of-window footers reported by the render pass. These are design renders, not native screenshots/tests.

Representative original PNGs were visually reviewed for plan ready/unscanned/pending, unavailable locations, scanning away from origin, wide/compact inspector and results. The compact panel was corrected to remain above the fixed footer. Other renders are available for inspection; no blanket native accessibility or OS claim is made.

Public preview-control observations: Explorer→folder→inspect→existing plan ends at plan without a cycle; Select all→confirmation Cancel keeps six exact sample choices; Forget Downloads in overlap fixture identifies one dependent choice and retains the independently supported Media choice. None of these actions reads or changes real files. Native verification remains on the implementation issues.

**Verdict: pending user visual review.** Flow/presentation decisions are approved; this artifact is a concrete proposal for those decisions, not a declaration that production repair is complete.
