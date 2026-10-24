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

Expanded run40048533746 passed 11 of13 cases, including retry, scan-away/cancellation, keyboard focus, Explorer checkbox anchoring and scrolled category anchoring. It exposed a 52-point plan-category shift and a missing unknown-coverage accessibility identifier. Candidate fixes are undergoing focused verification; these failures remain open. A broader existing Overview test also revealed a large-list hang under investigation. No full-suite success is claimed.

## Remaining qualification

Final-source public journeys, regression results and original Light/Dark initial/minimum captures will be recorded here after completion. Native permission revocation, sandbox/provider behavior, VoiceOver and supported OS/CPU qualification remain separate gates. No personal files were cleaned, no adapter was enabled, and no M8 distribution work was required.

Review also identified refreshing-content retention and named empty-coverage presentation gaps; fixes and public verification remain in progress. Included-but-never-scanned multi-location coverage aggregation remains on #46/#44, and caller-aware History recovery return remains on #48.

The full acceptance of #44/#46/#47/#48/#50 and every FL01–FL14/overlap branch remains open until proven; this first connected slice does not close #45 or remove future milestones.
