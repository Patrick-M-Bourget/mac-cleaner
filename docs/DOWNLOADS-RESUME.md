# Downloads implementation checkpoint

User requested a wrap-up before `/clear`. Resume this work before building further features. This is an unfinished verification checkpoint, not a delivery or merge approval.

## Repository and authority

- Repo: `/Users/bender/Library/Caches/Codex/mac-cleaner-implementation/repo`
- Working branch: `implement/downloads-journey`; latest implementation `b1702ef` (this checkpoint adds docs only).
- Integration: `integration/still-spec`, still at `9eb94fa`. Draft PR36 remains open on integration; feature changes have not yet been integrated. Do not mark it ready or merge failed checks.
- Approved proposal: `b96bb97`; FLOW-LOCK Q1–Q30. Read AGENTS, docs/README, SPEC, DESIGN-HANDOFF, DESIGN-SYSTEM and validation/connected-downloads.md.
- GitHub tracking: #55 → #56 → #57 under #45. All remain open pending final qualification/integration. Full parent repairs #44/#46/#47/#48/#50 and future milestones remain open.

## Implemented

Remembered explicit scopes with guarded security-scoped bookmarks; no restored observations/authority. Contextual Downloads prerequisite in stable plan; scans stay on origin; shared toolbar Stop/return. Shared exact macro/inline selection, observed folder Explorer/search/inspector/Back, immutable confirmation, disposable native Trash results, History/new-plan/relaunch. Optional initial viewport offset fixes native52-point shift. Explorer highlight no longer rebuilds/sorts full observations for every row. Latest `b1702ef` retains observed refinement during refresh with disabled stale selection and names empty scanned coverage.

Spec, design handoff/system, development and parity checkpoint are synchronized. Original native Light/Dark captures at intermediate `ffd11f7` are committed with manifest/hash/dimensions. Its initial unscanned capture shows the old inset bug, explicitly recorded; replace/add final-source captures rather than treating intermediate geometry as accepted.

## Proven results

- Local Xcode27.1 build-for-testing passes latest implementation: `/tmp/still-downloads-build-b1702ef.log`.
- Core131 Swift Testing +5 XCTest =136 pass: `/tmp/still-downloads-core-current.log` (use DEVELOPER_DIR below).
- Native40049450365 (`ffd11f7`): four tests pass, both complete journeys, contextual prerequisites and Gallery. Includes native fixture Trash, empty state, omit/reinclude, relaunch and wide/compact inspector geometry.
- Native40050359141 (`caf6375`): all3 exact-frame anchoring tests pass (plan category/individual, Explorer, scrolled category). The reproduced52pt displacement is resolved.
- Native40050233027 (`9ce57e0`): repair suite passes (exclusions + existing refresh).
- Standards/safety review: no remaining documented blocker in shared components, grant leases, exact overlap membership, omit/Forget or reset. External review notes: `../notes/downloads-journey-review.md`.

## Check running jobs first

At wrap-up these were still active/queued. Fetch actual results; do not assume success:

| Run | Source | Purpose |
|---|---|---|
|40050266396|caf6375|Expanded13-case Downloads suite before final refresh-display fix|
|40050412990|7a74e91|Recovery + Growth + Overview regressions; lacks later Explorer performance fix|
|40050757234|39832ca|Intentional red: expanded refinement must remain during refresh|
|40050922744|b1702ef|Final candidate expanded Downloads suite including new refresh/empty assertions|

Run40050736278 was redundant and deliberately cancelled after all3 anchoring tests passed.

**Open failure:** run40050435403 at `f5fe3ef` got through600-file browsing/search, selection and partial coverage without the previous event-loop hang, then failed WorkspaceUITests.swift:423 waiting for unavailable Downloads finding to contain Unknown after deleting the test-owned root and scanning remembered scopes. Diagnose actual rendered/accessibility state and coverage projection; do not assume it is only an assertion issue or weaken Unknown/no-false-empty requirements. Log `/tmp/still-overview-f5-failure.log`. Rerun unchanged public Overview journey after correction.

Earlier broad run40047017039 exposed Recovery's old Nothing selected assertion, Growth's legacy auto-navigation/unremembered scan path, the52pt shift, Overview hang and unknown coverage identifier. Recovery assertions, Growth route, inset and identifier have candidate fixes; confirm pending targeted results. Unaffected broad classes passed (retry, diagnostics, exclusions, history, managed inventory, alerts). Do not claim full-suite success.

## Next actions

1. Read latest run results and exact failure output; fix remaining regressions under existing approved public test boundaries. `downloads-refresh` provides intentional red comparison; `downloads`, `downloads-regressions`, `overview-main`, `selection` are available workflow inputs.
2. Check `b1702ef` refresh rows preserve names/query but never select stale evidence; source review plus current public assertions, no personal files.
3. Preserve original final-source native captures and actual dimensions, visually review Light/Dark initial/minimum including unscanned/header, empty, results and inspector. Update validation with exact source/run boundaries.
4. Finish review/evidence, package a source-named local app from successful build. Only then FF feature into integration, push/update draft PR36 and resolve child tickets whose acceptance is proven. Keep broader parent repairs open.
5. Clean only owned worktrees once all changes committed and proof preserved; current worktrees listed by git worktree list. They are shell-created, not managed app attachments.

## Commands and locations

```sh
cd /Users/bender/Library/Caches/Codex/mac-cleaner-implementation/repo
gh run list --branch implement/downloads-journey --limit 12
gh run view RUN_ID --log-failed
gh workflow run native.yml --ref implement/downloads-journey -f suite=downloads
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Packages/StillCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project Still/Still.xcodeproj -scheme Still -destination 'platform=macOS' -derivedDataPath .build/xcode
```

Local UI automation startup times out before assertions; use hosted macOS26/Xcode26.6 for native UI proof. No repeated personal app launch/access changes needed. Download native-test-results to a new external notes directory; artifact contains xcresult contents directly. Export with Xcode xcresulttool using DEVELOPER_DIR. Existing results/captures in `/Users/bender/Library/Caches/Codex/mac-cleaner-implementation/notes/downloads-*`.

All test filesystem actions use owned disposable fixtures. No personal cleanup, adapter promotion, signing/notarization or M8 work. Included-but-never-scanned multi-location aggregate coverage remains explicitly tracked on #46/#44, and History recovery's caller-aware return on #48. Existing skill/test-boundary approvals persist; do not re-grill approved flows.
