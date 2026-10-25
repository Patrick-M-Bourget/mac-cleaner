# What grew #52 — implementation evidence

Contract: [WHAT-GREW](../WHAT-GREW.md), Q1–Q17 user-confirmed October25,2026. G01–G04 remain pending complete native/source/visual qualification. M4 stays gated. This report records actual incremental evidence, not completion of the ticket.

## Core first slices

Source5868d2f. Existing approved public metadata/growth-policy boundaries; disposable files only.

- New location: real red incorrectly returned Coverage changed and an unrelated interval endpoint; green independent first baseline, then returning to the original location compares its own preceding observation (+4 logical bytes).
- Stop: real red erased the retained comparison; green keeps its exact observation and +4-byte result.
- Identity matching: initial compile red for absent public identity operation; green actual metadata accepts original root and rejects an unrelated same-named folder and replacement root at the original path. Does not grant access or start enumeration.
- Save failure: real corrupted disposable archive caused red loss of displayed comparison; green keeps its exact observation/+2 bytes and reports failure without claiming a new baseline.
- Partial scan: real one-entry limit caused red loss of comparison; green preserves it and retains only the original two baselines.

Full package run:154 Swift Testing tests plus5 XCTest pass (`/tmp/growth52-core.log`). This is Core policy/fixture evidence, not OS permission/provider qualification or native journey evidence. Existing test treating a different scope as changed coverage was narrowed to actual same-scope fingerprint changes, as Q5 explicitly supersedes the old cross-scope behavior.

## Follow-up Core slices

A real unavailable-location begin produced a red loss of comparison; green preserves its exact observation with an explicit identity/access error. A controlled91-day expiry followed by a real partial scan produced a red stale numeric comparison; green revalidates retained identity and displays Missing baseline. Preservation does not resurrect cleared/expired observations.

## Native and visual qualification

Pending. First public native tracer is being exercised before production changes. No new native pass, screenshot acceptance or parity coverage is claimed here yet.

## Core review corrections

Independent source review found two P2 gaps: preserving a numeric comparison when only its older endpoint expired, and inferring a missing per-location baseline from unrelated global history. Both received genuine public regression reds and focused greens in60f0490, integrated7c11a92. Unknown/partial results now re-read the exact comparison rather than only checking the selected endpoint; a newly recorded observation with no retained same-location predecessor establishes a baseline without claiming it is the first-ever scan. No schema or retention expansion. Full final Core158 Swift Testing+5 XCTest passes (`/tmp/growth52-core-review-full.log`).

## First native tracer

Run40226814851 was skipped by an initial focused-workflow filter and supplies no product evidence. Corrected red40226858665 at0f0d348 failed the intended missing “Scan to establish a baseline” action (9.948s); original inspected capture showed only the old “Inspect a folder” footer. Green40227101004 at091e526 passes that unchanged first-use journey after minimal production wiring. This is the first native slice only: location selector/review/historical/exceptional/final visual qualification remain pending. Original artifacts retained externally under artifacts/growth52-first-red and corresponding export; final capture acceptance not inferred.
