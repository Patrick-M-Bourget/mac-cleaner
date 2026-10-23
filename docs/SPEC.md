# Still — implementation specification

Revision 0.9 · October 22, 2026 · Native implementation handoff.

## Product outcome

Help people understand local storage, see what grew, choose specific cleanup actions and understand the result. Primary use case: a 256–512 GB Mac with iCloud and recurring storage pressure. All processing is local. No account or service is required.

Default behavior is on demand. A manual scan is read-only; selection is not execution. Optional Storage Alerts check startup-volume capacity only. No unattended cleanup or background recursive scanning.

## Full product scope

This table preserves the full product direction. It is not the first-build checklist. [Milestones](MILESTONES.md) assigns every feature to delivery stages; only M0–M1 are the initial build.

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

There is one live, session-only PlanDraft keyed by resource/action identity. Every checkbox in every view updates it immediately. Duplicate appearances share membership and count once. Inspecting a name changes only the inspector. Back and Cancel preserve selections. The item-review CTA is “View cleanup plan”; there is no staged apply step or inspector exclusion control.

Category selection materializes exact eligible IDs from the current scan. Downloads has the same unchecked/mixed/checked control, labelled with eligible count and bytes. It selects ordinary files, including ZIPs, PDFs, videos and installers within the scanned Downloads tree. It never targets the Downloads folder or other directories. Protected packages, managed libraries and unavailable files remain excluded. Show relative paths for nested files; record original and resulting Trash locations, without promising preserved directory structure or automatic restoration.

Selections persist across navigation and window closure while the process runs. Explicit Quit ends the unexecuted plan; next launch requires a fresh scan. Preferences, completed history and unresolved recovery records persist independently. No saved draft authorizes mutation.

A rescan retains selected identities as pending choices and suspends execution. On completion, revalidate retained targets, explain removed/changed targets and leave new discoveries unchecked. On cancellation keep choices visible with “Refresh required”; partial observations never make the old plan executable. Permission or volume changes similarly suspend affected choices. Execution performs its own fresh checks.

“Review cleanup” opens a summary with count, scope, total size, action/consequence and expandable exact targets. One explicit final approval freezes an immutable plan; no second per-file approval is required. Skip changed/unavailable targets and continue unaffected approved targets. Never replace targets, expand scope or change action without a new approval. Starting execution consumes the plan; unresolved items require recheck and new approval, not automatic repetition.

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

Retain local aggregate history under the detailed PRD policy (90 days, 30 completed baselines, 250 MB cap). Keep raw file observations transient where possible. Do not persist file contents, hashes, browsing contents or cloud credentials. Redact paths in diagnostics by default. Clear history removes completed records/baselines only. Unresolved intent/outcome journals are exempt from retention eviction and history clearing. Reset is blocked during execution or unresolved recovery, with a review route; when allowed it removes preferences/scopes and stops any alert/login registration. Future custom exclusions are also reset once that feature ships. Neither deletes original files or silently revokes OS grants.

## Build sequence and exit criteria

See [MILESTONES.md](MILESTONES.md) for the complete scope allocation and gates. M0 investigates iCloud opportunity and native feasibility. M1 builds inventory, shared selection, Downloads-to-Trash, confirmation, cancellation, truthful results and recovery. Growth, alerts, durable exclusions, diagnostics and permanent cache cleanup remain scheduled future work rather than first-build obligations.

## Required first-build regression journeys

- Empty plan → one Downloads file → plan → confirmation: exact ID/count/bytes.
- Downloads Select all → mixed refinement in another view: shared membership, no duplicate counting, no folder targets.
- Back, search, navigation and window closure preserve choices; explicit Quit clears the unexecuted plan.
- Rescan suspends execution, retains pending choices, validates survivors, explains removals and leaves new discoveries unchecked; cancellation requires refresh.
- Confirmation Cancel preserves choices; changed/unavailable targets are skipped without substitution or action changes.
- Crash recovery reconciles known facts, labels unknown outcomes and never auto-resumes or repeats mutations.
- Clear History cannot erase unresolved journals; Reset is blocked during execution/recovery.
- Trash failure leaves originals untouched; record individual original/resulting paths without hierarchy or Undo guarantees.
- Denied access still permits useful partial inspection; ordinary scans never hydrate cloud contents.
- Fixed window bounds, bounded sheets, scroll/focus restoration, keyboard operation and both appearances.

The historical [state matrix](reference/macos-cleaner-ui-state-matrix.md), [layout contract](reference/macos-cleaner-layout-contract.md) and [detailed technical spec](reference/macos-cleaner-technical-spec.md) provide the remaining acceptance branches. Before release, validate iCloud pin/sync detection, browser mappings, filesystem accounting, minimum OS and privacy-manifest requirements against current Apple documentation and real disposable fixtures.
