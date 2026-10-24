# Connected Downloads journey

October 23, 2026. Approved contract: [FLOW-LOCK](../FLOW-LOCK.md), visual proposal b96bb97 and [design review](../CONNECTED-FLOW-DESIGN-REVIEW.md). Implementation tickets: [#55](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/55) → [#56](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/56) → [#57](https://github.com/Patrick-M-Bourget/mac-cleaner/issues/57), parent #45.

**Validation is in progress.** This record will distinguish final-source native proof from intermediate results; it is not a full parity completion claim.

## Implemented composition

- One Cleanup plan hierarchy before/after scanning: summary → Downloads category/prerequisite → fixed Review. No permanent plan chooser/banner. First access is contextual; scans stay on the initiating destination and never select files.
- Remember explicit scopes/inclusion using bounded local security-scoped bookmarks. Add never scans. Explicit scans/selection/preview/retry/execution resolve grants; stale/moved/unavailable grants do not silently renew. Quit restores configuration only.
- Shared macro and collapsed inline selection feed the existing exact immutable confirmation/executor. Cancel retains membership. Pending selected files block review with explicit deselection; valid independent evidence remains available.
- Observed-only Explorer has selected location roots, folders, breadcrumbs, descendant search and separate adaptive inspector. File inspection, folder navigation and selection are different actions. Context and viewport survive in-process navigation; direct sidebar navigation creates no Back chain.
- Results offer History and a new plan. Consumed work cannot execute again; a new plan has no selections and requires manual scanning.
- Shared design APIs: CategoryPrerequisite, ToolbarScanStatus, LocationScopeRow, ExplorerInspector and native viewport restoration. Domain observations/selection, not View formatting, own eligibility, overlap and accounting.

## Evidence so far

Local Xcode27.1 builds the runnable app/test runner. Local XCTest UI startup timed out enabling automation before reaching assertions; hosted macOS26/Xcode26.6 supplies native journey execution. Core tests pass: 131 Swift Testing tests plus 5 disposable registry XCTest tests (136 total), including exact overlap rebinding, expired-proof protection, malformed persistence and root-symlink rejection.

[Run40049450365](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40049450365), source `ffd11f7`, passed all four focused tests: both complete public Downloads journeys, contextual no-scan prerequisites across appearances, and minimum Gallery states. Journeys cover native disposable Trash, relaunch without observations/membership, empty results, omit/reinclude, descendant search/no matches/Back and responsive inspector geometry. [Original captures](../visual/connected-downloads/ffd11f7/manifest.json) retain hashes, source, test run and actual PNG dimensions: initial 1024×640 and minimum 900×640. Native screenshots are not browser renderings or a claim that the hosted display allowed the requested 1120×760 window. Visual review confirmed white Light sidebar, dark reading plane, stable sibling footer and wide/compact inspector separation. The initial unscanned capture also shows the same toolbar-inset displacement found by anchoring tests; it is retained as intermediate evidence, not accepted final geometry.

Expanded run40048533746 passed 11 of13 cases, including retry, scan-away/cancellation, keyboard focus, Explorer checkbox anchoring and scrolled category anchoring. It exposed a 52-point plan-category shift and a missing unknown-coverage accessibility identifier. The unknown-coverage fix is undergoing expanded verification. [Anchoring run40050359141](https://github.com/Patrick-M-Bourget/mac-cleaner/actions/runs/40050359141), source `caf6375`, passed all three unchanged exact-frame tests: plan category/individual checkboxes, Explorer checkboxes and scrolled category. The optional initial viewport offset fixes the reproduced native toolbar-inset displacement. The large-list optimization at `f5fe3ef` allowed run40050435403 to finish folder browsing/search/selection and partial-coverage checks without the earlier event-loop hang. The test then failed its later unavailable-Downloads assertion (WorkspaceUITests.swift:423); this new failure remains to diagnose, not assumed to be a test-only mismatch. No full-suite success is claimed.

## Review

Standards review at `a2845d2` found no remaining documented violation. The prior domain-policy-in-View and status-copy-driven-action findings were fixed. Two native viewport bridges remain a nonblocking duplication concern; their restoration events differ, and consolidation is deferred to preserve verified behavior.

Spec/safety review confirmed configuration-only persistence, explicit balanced access leases, unchanged exact overlap membership, omit/Forget distinction, guarded reset and a new-plan boundary without restored authority. A final flow review found refreshing-content retention and missing named empty coverage; `b1702ef` addresses both, with native red/green qualification still running. Source review does not certify OS permissions, providers or full parity.

## Remaining qualification

Final-source public journeys, regression results and original Light/Dark initial/minimum captures will be recorded here after completion. Native permission revocation, sandbox/provider behavior, VoiceOver and supported OS/CPU qualification remain separate gates. No personal files were cleaned, no adapter was enabled, and no M8 distribution work was required.

Review also identified refreshing-content retention and named empty-coverage presentation gaps; fixes and public verification remain in progress. The included-but-never-scanned coverage correction is now in `824328f` and remains under qualification; full multi-location acceptance stays on #46/#44. Caller-aware History recovery return remains on #48.

The full acceptance of #44/#46/#47/#48/#50 and every FL01–FL14/overlap branch remains open until proven; this first connected slice does not close #45 or remove future milestones.

## Resumed verification

Run40050266396 (`caf6375`) passed all13 expanded cases. Run40050757234 (`39832ca`) reproduced the missing expanded refinement during refresh at WorkspaceUITests.swift:1249; `b1702ef` addresses it and names empty coverage. Its expanded native run40050922744 remains running at this update.

Run40050412990 failed Recovery's text-label query and Growth's Overview-only readiness query, as well as the known earlier large-list path. `d8481d6` uses Recovery's existing stable summary identifier and Growth's own completed-state evidence, preserving zero-selection/no-authority and complete growth assertions. Native regression40051984202 checks these with the current app.

The later Overview failure exposed a coverage error: retiring an inaccessible scan could make failed Downloads coverage read Not inspected. `824328f` retains Unknown for explicit remembered access failures and compares current observations with included configuration. Omitted locations are excluded; fresh re-inclusion remains unscanned. A minimized public native regression uses a validated disposable Downloads root (`19fd3d1` red, `824328f` candidate). Runs40051942964 and40051982017 provide this comparison. Run40051875862 used an unrecognized fixture root name and was cancelled; it is not valid diagnostic evidence.
