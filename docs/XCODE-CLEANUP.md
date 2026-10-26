# Xcode generated-data cleanup — #16/#17

Status: grilling in progress. Q1–Q3 were confirmed by the user on October26,2026. Remaining decisions are not locked; this document does not authorize implementation or enable cleanup. #16 is unblocked capability work; #17 remains blocked by #16. SPEC and DESIGN-HANDOFF remain the consolidated entry points.

## Confirmed decisions

1. **Deliver the feature journey.** Complete #16’s remaining qualification, then deliver #17’s developer-data discovery, shared selection, permanent confirmation, execution and truthful results/History. Reuse the approved prototype and native design system. Existing genuine C and Swift/package experiments are retained evidence; do not repeat them or substitute another standalone probe for the app journey.
2. **Initial artifact scope.** Start with verified, project-specific generated build intermediates, not whole DerivedData folders. Preserve source, archives, dSYMs, build products, package checkouts, indexes and module caches. Additional generated-data categories remain future scope until independently qualified. A familiar filename or path alone does not establish eligibility.
3. **Owner activity.** Read-only inspection may run with Xcode open. Cleanup requires Xcode and relevant build processes closed. Explain blocked/unknown states, offer explicit manual recheck, never terminate owners or remove locks, and stop unstarted work if activity appears.

## Remaining decision frontier

- Define practical concurrency/race guarantees without silently importing Chrome’s group-approval exception or the historical universal-exclusive-access prerequisite.
- Choose project/group refinement and how it maps to exact approved artifacts.
- Define explicit inspection enablement and initial standard/custom-root scope.
- Resolve downstream refresh, stale selections, confirmation, partial outcomes and recovery differences where existing shared contracts do not already settle them.

## Existing evidence and boundaries

[Fixture policy](../Validation/XcodeProbe/README.md), [genuine owned-project experiment](../Validation/XcodeProbe/NativeExperiment/README.md) and [Swift/package/custom-output follow-up](../Validation/XcodeProbe/NativeExperiment/SWIFT-SESSION.md) establish bounded generated-object removal/regeneration and protected owned sentinels. They do not establish arbitrary production project mapping or general build-owner coordination. Historical exclusive-access language is not superseded until the user confirms a revised Xcode contract.

No personal projects, default DerivedData or source/symbol contents are inspected by grilling or ordinary verification. Qualification remains disposable. Downloads and all personal-file protections are unchanged. Release-archive guidance remains separate under #54. Broader developer/browser support and M8 commercialization remain preserved.
