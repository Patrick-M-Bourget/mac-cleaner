# Still — implementation specification

Revision 0.8 · October 22, 2026 · Native implementation handoff.

## Product outcome

Help people understand local storage, see what grew, choose specific cleanup actions and understand the result. Primary use case: a 256–512 GB Mac with iCloud and recurring storage pressure. All processing is local. No account or service is required.

Default behavior is on demand. A manual scan is read-only; selection is not execution. Optional Storage Alerts check startup-volume capacity only. No unattended cleanup or background recursive scanning.

## Scope

| Capability | v1 boundary |
|---|---|
| Inventory | Selected folders and explicitly enabled known locations; metadata and allocated/logical sizes with honest coverage |
| Growth | Two completed, compatible scan snapshots; distinguish coverage changes from growth |
| Cleanup plan | Exact targets selected through categories or item review, consequence-specific confirmation |
| Ordinary files | Native Move to Trash; no permanent fallback and no automatic Trash emptying |
| iCloud downloads | Local eviction only after validated sync/pinning checks; guidance when unsupported |
| Developer data | Xcode DerivedData first; release archives protected. Homebrew/pip conditional on validated adapters and dedicated review UI |
| Browser caches | Chrome/Safari candidates, independently gated by OS/browser fixtures; asset caches only |
| App-managed storage | Read-only inventory and guidance for backups, Photos, Mail/Messages and system-managed data |
| History | Local action records, aggregate snapshots, clear history and reset flows |
| Alerts | Off by default; optional capacity polling, notification authorization and separate Start at Login |
| Diagnostics | Redacted review followed by explicit local Save; no automatic upload |

Deferred: app uninstall, duplicate detection, direct backup deletion, Docker mutation, other browser support, FSEvents monitoring, automatic cleanup, account/cloud services and treemap-first navigation.

## Platform and architecture

- Swift 6, SwiftUI with focused AppKit bridges, Xcode and Swift Package Manager.
- Provisional macOS 14 minimum, Apple silicon first. Intel/universal distribution requires actual test coverage.
- Direct Developer ID distribution, Hardened Runtime, notarization; initially unsandboxed, logged-in user privileges only. No root helper.
- Foundation metadata/file operations; bounded background I/O. Swift concurrency for orchestration; never block MainActor or create a task per file.
- SQLite behind a repository with migrations, one writer and batched writes.
- Swift Testing for policies/fixtures; XCTest UI tests for key journeys.

Pipeline: scoped metadata discovery → observations → versioned classification rules → findings → mutable plan draft → approved immutable plan → revalidation/executor → journal/results. Only the executor may mutate cleanup targets. The capacity monitor cannot invoke the scanner or executor.

Core types: ScanScope, ScanSession, FileObservation, StorageSnapshot, Finding, PlanDraft, CleanupPlan, ActionRecord, AlertPreferences and AlertEpisode. Preserve resource identities, scope/rule versions, timestamps and completeness rather than passing bare paths/byte totals between layers.

## Selection and navigation contract

There is one committed PlanDraft keyed by exact target identities. Category selection materializes currently eligible IDs; unchecked/mixed/checked states derive from that set. New eligible targets are never silently added.

Separate item review starts a scoped editing draft from PlanDraft. “Add selected items to cleanup plan” atomically replaces membership within that reviewed scope, preserves all other scopes and opens Cleanup plan. If clearing an existing scope, use “Update cleanup plan”. Back abandons unapplied edits; reopening loads committed membership. Inline plan refinement edits PlanDraft directly. Keep this distinction explicit in state types, not duplicated booleans.

Review entry never selects anything by itself. Inspecting a filename only updates its inspector. There is no inspector “Exclude from cleanup” control. Persistent scan exclusions remain a separate settings concern.

“Review cleanup” freezes the proposed targets and opens confirmation. Final approval is separate. Changed targets invalidate approval or are skipped after revalidation; never substitute newly discovered targets. Starting/completing execution invalidates general plan reuse. Retry requires a fresh recheck and new approval of only unresolved targets.

A full successful rescan resets selection. Cancelled scans retain prior observations with freshness labels. Refreshing browser activity can remove ineligible targets but cannot add new selections. Navigation never starts a scan or changes window size.

## Filesystem correctness

- Stay within explicit scopes; do not follow descendant symlinks or silently cross volumes.
- Do not read content or hydrate cloud placeholders during ordinary scans.
- Keep logical bytes, allocated bytes, estimated release, Trash-held bytes and observed volume change distinct. Unknown is never zero. APFS sharing/snapshots prevent exact exclusive-space promises.
- Revalidate containment, identities, symlink ancestry, access, exclusions, modification state and action-specific preconditions before mutation. Include target-swap race fixtures.
- Journal intent and outcome per target. Cancellation stops new work; no all-or-nothing rollback claim. Reconcile interrupted operations without blindly retrying them.
- Trash failure leaves the original untouched. Cloud eviction never uses ordinary deletion. Permanent cache/tool cleanup requires explicit consequence disclosure.
- Protect system files, app bundles, release archives, backups and user databases from generic rules.
- Browser allowlists exclude cookies, credentials, history, site/offline storage, sessions/tabs, autofill and downloads. Unknown versions/layouts or uncertain inactivity fail closed.

## Permissions and lifecycle

Ask for folder access in context. Full Disk Access is optional expanded coverage, not onboarding admission. Handle denied/revoked access and missing volumes with partial coverage. No Accessibility, Automation, Screen Recording, Apple Account login or administrator access is needed for this scope.

Notifications are requested only after alert opt-in. Start at Login is independent and reflects actual SMAppService status. With effective alerts, closing the window leaves the menu-bar app active. Explicit Quit stops monitoring at a safe operation boundary; it does not change login intent. Without effective alerts, no alert-only background work remains.

Alert defaults: 40 GB suggested threshold, decimal units, valid range at least 1 GB and below volume capacity. Sample roughly every 15 minutes while awake plus coalesced activation/wake. One notification per low episode; rearm at threshold + 5 GB capped at capacity. Snooze is 24 hours, with one low-space reminder after resumption. Persist suppression across launches and preference changes. Missing capacity pauses decisions. Opening an alert opens Overview and offers a scan, never starts one. The detailed technical spec defines failure and metric-change handling.

## Data and privacy

Retain local aggregate history under the detailed PRD policy (90 days, 30 completed baselines, 250 MB cap). Keep raw file observations transient where possible. Do not persist file contents, hashes, browsing contents or cloud credentials. Redact paths in diagnostics by default. Clear history removes records/baselines; Reset also removes preferences/scopes/custom exclusions and stops alert/login registration. Neither deletes original files or silently revokes OS grants.

## Build sequence and exit criteria

1. **Shell and design system:** six destinations, fixture-backed review/plan/results, light/dark themes, stable geometry and accessible controls. No filesystem mutation.
2. **Read-only vertical slice:** folder access → metadata scan → coverage/Overview → compatible growth snapshots. Validate cancellation and no cloud hydration.
3. **Planning and ordinary Trash:** exact identity selection → immutable approval → revalidation → journal → per-target result, using disposable fixtures first.
4. **Conditional adapters:** Xcode, cloud and browser capabilities enabled independently after safety/compatibility gates. Guidance is the fallback.
5. **Alerts and local management:** persisted episode policy, native notifications/login lifecycle, diagnostics save and reset.
6. **Release hardening:** performance, localization/accessibility, supported OS matrix, signing/notarization and clean-machine install/uninstall.

## Required regression journeys

- Empty selection → one file → plan → confirmation: exact ID/count/bytes; no implicit neighbors.
- Macro selection → mixed refinement → item review → apply: same targets, no duplicate IDs or lost other categories.
- Clear every item in a reviewed scope → Update plan: only that scope removed.
- Back/Cancel returns context and scroll; unapplied edits do not mutate the plan.
- Reload/relaunch restores saved scope and target membership after scenario/domain initialization, never default sample selection.
- New browser eligibility remains unchecked; revoked access removes actionability.
- Scan cancellation, execution cancellation, crash reconciliation and targeted retry never repeat completed targets.
- Protected browser-data sentinels remain unchanged; unsupported adapters offer guidance.
- Capacity polling never calls recursive scanning; notification denial preserves on-demand use.

The [state matrix](reference/macos-cleaner-ui-state-matrix.md), [layout contract](reference/macos-cleaner-layout-contract.md) and [detailed technical spec](reference/macos-cleaner-technical-spec.md) provide the remaining acceptance branches. Before release, validate iCloud pin/sync detection, browser mappings, filesystem accounting, minimum OS and privacy-manifest requirements against current Apple documentation and real disposable fixtures.
