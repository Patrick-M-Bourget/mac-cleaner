# #52 Core review fixes

Branch `feature/what-grew-52-core-review`; base dce5c86; fix commit `60f0490`; merged current integration tip, resulting head `7c11a92655343306d65a1a3528640ddc0e91ee99`. No push. Clean worktree. Core only.

Approved public seams: GrowthHistoryStore, GrowthHistorySession, recorder. Disposable real filesystem; controlled historical dates; no new test seam or archive schema.

1. `partialScanRevalidatesComparisonWhenOnlyItsOlderEndpointExpires`: genuine red exposed `.compared` and +2 after the older endpoint aged out but newer remained. Log `/tmp/growth52-core-endpoint-red.log`. Minimal change re-queries the exact selected ID for unknown recorder results, preserving race guards and clearing numeric comparison if prerequisite predecessor is unavailable. Focused green `/tmp/growth52-core-endpoint-green.log`.
2. `expiredUnrelatedHistoryDoesNotClaimANewLocationLostItsBaseline`: genuine red returned `.missingBaseline` for first B observation after unrelated A expired. Log `/tmp/growth52-core-location-red.log`. Removed unrelated global `hadHistory` from newly recorded entry origin. No retained same-location predecessor means baseline established (`.firstBaseline` internal name); existing retained entry origins continue distinguishing evicted prior baselines. Global empty-archive history explanation unchanged. Focused green `/tmp/growth52-core-location-green.log`.

Full `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Packages/StillCore`: 158 Swift Testing + 5 XCTest pass. Log `/tmp/growth52-core-review-full.log`. Integration merge changed docs only after check; Core source/test tree unchanged. `git diff --check` passed.
