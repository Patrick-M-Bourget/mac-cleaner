# Final Standards source review — #52

Reviewed fixed point `8f0172a` through application source `bd14009` and current feature checkpoint `7f0e5bf`. Read-only; no tests rerun. Pending Gallery composition and original-image/native proof are excluded from hard source findings and remain separate integration requirements.

## Finding

**P2 — Guard stale failed comparison reads before committing presentation state.** `Still/App/GrowthHistoryView.swift`, `GrowthHistoryModel.complete`, final catch: the success path checks `displayRequest == request` and cancellation after its asynchronous store read, while its catch unconditionally sets `archiveUnavailable`, `openingError`, and clears `liveComparison`. If a lookup fails after a newer selection/load/history transition supersedes that request, the obsolete failure can replace the newer presentation. Apply the same request/cancellation guard before catch mutations. This follows the documented stale-response/session-preservation requirement and the adjacent load/select policy. Sent directly to the implementer. This is a bounded correction, not a request to expand test boundaries or architecture.

## Resolved / compliant

The earlier duplicate-location-menu finding is resolved: same-named retained roots receive a stable scope-derived suffix, without synthesizing paths or granting filesystem authority. Location-specific baseline selection remains separate from file-type grouping and cleanup selection.

Display generations now guard load/select successful responses and errors; independent authority generations and exact observation checks protect resolved location evidence. Scan/review routes verify root/volume identity using retained fingerprints and authorized leases, check route generation after suspension, close discarded leases, and retain destination-specific actions. No automatic historical-to-file selection or cleanup authority is introduced.

Shared SummarySurface, status/failure/progress components, token palette/type/rhythm, native controls and disclosure gutter remain consistent. Logical-size dimensions stay separate; signed values and direction headings supplement colour. New tests observe public journeys and disposable filesystem boundaries, retaining exact geometry and independent expected values.

No additional actionable maintainability smell. Existing model size/compressed formatting alone does not justify an unrelated refactor. No source-review finding certifies native permission behavior, complete Gallery states or visual fidelity.

## Targeted supplement — `78a0c31`, `08a3485`, `5a82e16`

The P2 above is resolved in candidate `78a0c31`: `complete`'s catch checks the exact display request and cancellation before changing archive/error/comparison presentation. No new actionable Standards finding in that correction.

Reviewed only the two-file History return-anchor correction at `08a3485` plus `5a82e16`. The process-only context records the explicitly clicked baseline link's viewport-relative position through a noninteractive native background marker. It does not persist selection, create scan authority or replace the shared navigation architecture. Weak native-view references avoid owning removed view trees. Restoration waits for both archive loads to settle and a deferred layout pass, then consumes the anchor before scrolling. Later checkbox/disclosure/theme updates cannot repeatedly trigger that consumed return adjustment. This is an explicit navigation restoration, consistent with the design-system distinction from selection-driven scrolling.

No source blocker found in this bounded change. Actual frame restoration remains a native behavior check: the reported failing historical journey is genuine red evidence, not yet green proof. No tests rerun or visual acceptance claimed by this supplement.

## Last narrow supplement — `fb20196`

Reviewed only the two-file feed-revision guard. No actionable source blocker. The local History anchor captures the displayed ordered item IDs at the explicit comparison-link click and compares them after both archive reads settle. If the feed is unchanged, it consumes the local anchor without scrolling, leaving the existing qualified destination-offset restoration untouched. Added/removed/reordered items retain the bounded link-relative correction. Revision and anchor remain ephemeral component context, with no persistence, domain authority, broad navigation API or checkbox-driven adjustment.

This is source review only. The reported four-method existing/new historical rerun `40230725235` remains the actual strict-frame behavior qualification; no tests or further visual review were performed for this nonvisual guard.
