# Explicit custom exclusions — issue #30

## Scope and public evidence

The semantics were committed before implementation in [EXCLUSIONS.md](../EXCLUSIONS.md). The M6-only secondary route is **Locations & access → Manage exclusions**, with shared `PageHeader`, `SettingsRow`, `StatusRow`, `SummarySurface`, `EmptyState` and fixed `ActionStrip`. It adds no sidebar item or new visual primitive. Preview/Save/Cancel and rule removal are explicit. Ordinary plan deselection does not access the rule store. Fixed scanner protections cannot be edited.

Six disposable public policy/store/scanner/selection/growth fixtures cover:

- Persistence/reopen, exact file versus folder-subtree rules, overlapping rule removal, rename, same-path replacement and different-volume mismatch.
- Skipping excluded descendants before metadata requests, unknown full totals with known included logical coverage, whole-scope exclusion remaining partial, and independent hardlink aliases.
- Changed exclusion coverage starting an incompatible growth baseline, then a compatible repeated observation; a scan with the wrong policy cannot establish a baseline.
- Existing selection becoming pending, a complete excluded scan clearing it with a notice, and rule removal leaving newly visible files unchecked.
- Coverage invalidation rejecting an old in-flight growth token while retaining completed historical aggregates.
- Corrupt saved settings failing closed, with explicit store reset preserving unrelated owned authority.

The new API slices failed before their implementation (missing policy/scan APIs, missing coverage-invalidation operation and exclusion-aware recorder begin), then passed. The corruption fixture additionally verifies existing failure behavior. The complete merged **StillCore suite passed 117/117** with Xcode 27.1. Debug native **build-for-testing passed**, including both new initial/minimum journey sources, and **Release build passed**. Current commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no global toolchain setting changed.

Growth capture preserves the original root/volume fingerprint and persisted recording epoch, adds the normalized rule fingerprint, and uses complete *included* logical coverage. Excluded bytes are never reinterpreted as zero or reclaimable. Rule changes rotate only growth recording authority, retaining historical aggregates. Guarded Reset uses the existing maintenance lease and fresh unresolved-journal guard, then clears custom rules alongside existing growth/alert/login/preferences and diagnostics reset paths. Clear completed history does not clear rules; unresolved journals are never retention-evicted.

## Native qualification gate

The bounded local initial journey failed **before any UI action**, at `app.launch()` activation after approximately 61 seconds: XCTest reported the app in `Running Background`. It did not reach picker, preview, Save, scan or removal. No permission/security changes or OS warning workaround were attempted. The local result is `.build/exclusions-initial.xcresult`; log `/tmp/still-exclusions-ui-initial.log`. This is not a passing native workflow or visual qualification.

`ExclusionsUITests` contains initial/minimum owned-fixture journeys for explicit picker → preview → Save, relaunch persistence, scanning only included entries, Light/Dark stable bounds and fixed Back reachability, and explicit rule removal with unchanged originals. Both require a clean native runner before acceptance. New preview/empty/populated/error/changed-coverage states still need unobscured Light/Dark review at initial and minimum bounds. No screenshots from the blocked attempt are presented as approved evidence. The existing white light-sidebar and dark shared-surface policy are reused unchanged.

All automated data is disposable. No personal folder, file contents, browser profile, cloud download or cleanup mutation was inspected or requested.
