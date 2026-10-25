# #52 final business/source Spec review

Scope: fixed point `8f0172a` through production source `bd14009` in `feature/what-grew-52`; later `3df120f`/`7f0e5bf` are test-only checkpoints. Authority: locked `docs/WHAT-GREW.md` Q1–Q17. Read-only; no scope expansion or decisions reopened.

**No outstanding actionable source Spec findings.** The three prior App P2 findings are resolved: thrown scan failures now publish a retained-comparison outcome through `GrowthHistoryModel.failed`; review captures route generation and exact selected observation before awaiting authority and validates both before routing; reconnect scanning revalidates caller, original observation and shared scan availability after the final lease await, closing stale leases. Authority resolution now has distinct checking state and request guards.

Contract coverage at source level:

- Q1–Q2/Q5–Q6/Q11: manual, location-specific complete observations; same-location immediate predecessor; incompatibility is explicit; no unrelated fallback. Conservative baseline-established wording avoids invented first-ever/missing causes. Existing retention limits remain unchanged.
- Q7/Q13/Q14: one shared scanner, guarded starts, visible progress/Stop, explicit partial/stopped/failed explanations, retained comparison revalidation, archive Retry and truthful unsaved-result error. No automatic scan/replay or completion navigation.
- Q3/Q9/Q10/Q12: verified remembered authority or explicit identity-checked reconnect; current findings determine Review Downloads versus Explore folder versus Scan to review. Historical labels never construct authority. Existing selection/approval remains governed by current plan/refresh rules; caller routes retain model state and growth viewport.
- Q4/Q15: exact History UUID remains separate from current selection; missing historical records never substitute a newer comparison; explicit new scan switches to current while direct Back to History survives. Picker cancellation precedes that transition.
- Q8/Q16/Q17: logical-size summary with actual endpoints, distinct folder/file-type views, signed changes, deterministic magnitude ordering, shared scaling, readable tiny values, and no reclaimable/writer attribution. M4 gate stays intact; future capabilities remain deferred.

**Remaining qualification gates, not source findings:** native public journey results, affected regression checks, completed shared Gallery families and original Light/Dark visual review. This report does not certify OS authority behavior, screenshots/layout stability, or declare #52 qualified. Subsequent Gallery review should be visual-only unless production behavior changes.

## Targeted History return supplement — 08a3485 + 5a82e16

Reviewed only `ScanActivityHistory.swift` and `CleanupHistoryView.swift` for the actual-red-driven exact-link return adjustment. **No source blocker found.** The process-only context records the clicked baseline UUID and its viewport-relative vertical position; waits for the destination to depart and both History stores to finish reloading; then adjusts the exact returning link after insertion/layout. It consumes the anchor once before scrolling, so subsequent checkbox/disclosure/theme updates cannot repeatedly reposition the viewport. Existing filter/disclosure ownership and cleanup selection are untouched; there is no persisted authority or general navigation API. Bounded clip constraints appropriately limit restoration at document edges.

This resolves the source omission exposed when a newly recorded scan prepended History content. Actual exact-link frame restoration and subsequent interaction stability remain native-test/visual evidence questions; the earlier failed run 40228922318 is not acceptance evidence. No new tests or scope requested by this supplement.
