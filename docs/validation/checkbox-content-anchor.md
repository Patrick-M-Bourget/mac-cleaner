# Checkbox content movement — reproduced and focused fix verified

The first user recording exposed the missing sequence: toggle the category checkbox after scrolling Cleanup plan so its summary is above the viewport. Private recordings and filenames are not published here.

## Reproduction and correction

A native disposable 120-file fixture reproduced a 206-point displacement after category selection settled, while the outer window frame remained unchanged. The minimized baseline is `a94b0110ed5a486767464d13eb75e3bb33f0545f`, [run 39976582488](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39976582488). A nine-file fixture passed on the hosted OS, so reproduction depends on layout; that does not exclude the user's smaller real case.

Application commit `f3abbda84f5f6feb327e07cd84ccbb220fcc9e44` removes row-ID scroll-position tracking and its nested lazy-list target layout from the mixed summary/list scroll pane. Native scrolling now retains the viewport through selection updates. Selection policy, exact-target approval and execution are unchanged.

- Scrolled category regression: **1/1 passed**, 36.546 seconds, [run 39977256055](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39977256055).
- All focused checkbox journeys: **3/3 passed**, 113.879 seconds, [run 39977692198](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39977692198). Includes plan category/item selection, inspection item selection and scrolled category selection.
- The earlier full [run 39977247187](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39977247187) passed 36/37; an exclusion-picker test selected the parent folder rather than its intended file. The exact preview precondition is now verified. Final application `7d12f12` passes all three anchor journeys in [run 39982396498](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/39982396498), 87.614 seconds. Final full verification is recorded with [scope guidance](downloads-scope-guidance.md).

The native checks establish full visibility using the actual scroll viewport, await public selection state and enabled controls, and compare both outer window and clicked-control frames. Accessibility hit testing alone previously admitted offscreen controls and caused an invalid harness failure; it was corrected before the minimized reproduction.

Original synthetic before/after captures and exact source/run/hash provenance are retained in [the capture manifest](../visual/checkbox-content-anchor/manifest.json). Hosted tests use macOS 26.6.2/arm64. Local Xcode 27.1 Debug and Release builds pass; the initial fixed candidate was `Still-f3abbda.app`; current candidate `Still-7d12f12.app` also includes the scope guidance and disabled-review correction. The user reports it is better; this is not yet an exhaustive manual confirmation that every jump is gone.

## Separate scope confusion from the second recording

The second recording shows successful inspection of non-Downloads locations, followed by an empty Downloads cleanup category. This follows M1's Downloads-only mutation boundary, but the explanation is insufficiently prominent. Inspection of an explicitly selected folder does not make its files eligible for cleanup. Files selected within Downloads do carry into the plan in the recording.

Implemented follow-up: [shared scope guidance and the Downloads shortcut](downloads-scope-guidance.md) now explain the boundary before and after inspection, including both empty and live plans. Per-row lock tooltips and empty-plan copy are no longer the sole explanation. Keep broader ordinary-file cleanup and whole-folder cleanup separate product decisions; neither is enabled by this fix. No personal files were mutated during this investigation.
