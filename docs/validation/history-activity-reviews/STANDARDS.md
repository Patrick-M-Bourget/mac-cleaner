# Standards supplement — #51

Frozen source: `f062ca6`. Reviewed supplemental diff `0433ff7...f062ca6` and the original reload finding against cumulative `c5b8e9a...f062ca6`. Source/fixture inspection only; no tests run or repository edits. Native capture review remains separate and pending.

## Hard findings

**Original P2 resolved.** `Still/App/CleanupHistoryView.swift:157–162` now renders separate `HistoryStoreFailure` controls: cleanup retry invokes only `model.load()`, while scan retry invokes only `scans.load()`. Scan retry has its own loading state. Initial page loading also starts both reads concurrently. This satisfies the independent warnings/reload requirement in `docs/DESIGN-SYSTEM.md` (History activity locked composition). The added public fixture journey explicitly checks that retrying scans leaves cleanup unavailable until its own action is activated; execution results are outside this review.

**No additional hard standards breaches identified** in the supplemental source. Shared pure feedback/empty/unavailable/retention views are reused by live composition and the DEBUG Gallery. Gallery covers terminal outcomes, unattempted roots, same-named roots, unknown measurements, long paths, independent failures, filter-specific empties, recording failure and partial maintenance with inert actions. Expanded paths use vertical fixed sizing, full-width leading alignment and the shared disclosure gutter; compact summaries may truncate with help text. This establishes source conformance, not visual acceptance.

## Optional smell judgement

**String reason vocabulary remains an acknowledged maintainability smell, not a hard violation.** Read `/Users/bender/Library/Caches/Codex/mac-cleaner-implementation/notes/history51-reason-schema-judgement.md`. Deferring a persisted-key refactor is reasonable for this bounded slice: version-1 dictionaries have explicit privacy validation and UI labels, while changing key representation requires a wire-format compatibility decision. The whitelist, classification set and presentation mapping still require coordinated updates when adding reasons. No present correctness failure follows merely from the representation, and this does not block integration once remaining qualification gates pass.
