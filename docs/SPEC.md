# Still — implementation specification

Native UI implementation follows the mandatory [design system](DESIGN-SYSTEM.md).

Revision 0.9 · October 22, 2026 · Native implementation handoff.

## Prototype parity checkpoint — October 23, 2026

The [parity audit](PROTOTYPE-PARITY.md) traces current gaps and retained future capabilities. User-confirmed grilling Q1–Q30 now locks the connected [product flow contract](FLOW-LOCK.md) for #44/#46/#47/#48 and the results boundary in #50. These are approved requirements, **not implemented parity claims**.

The plan retains a stable category workspace with contextual scan prerequisites; Locations manages remembered explicit inclusion; Explorer navigates existing observations and shares selection; contextual Back preserves caller state without cycles. Scans never navigate on completion. Selected pending files block approval until checked or deliberately deselected. Completed runs lead to separate results and a fresh unselected new-plan boundary. See FLOW-LOCK for every decision, return route and FL01–FL14 state.

Presentation/delivery decisions and the [annotated visual proposal](CONNECTED-FLOW-DESIGN-REVIEW.md) were approved by the user on October 23, 2026. Connected implementation may proceed in the agreed Downloads-first sequence; do not re-grill settled flows or resume isolated screen work. Keep the approved white/near-black native design, existing shared components and all future milestones. Remaining #51–#54 decisions/gates are preserved; #49 now follows the separately confirmed capacity contract below. None is a blanket prerequisite for M1. M8 remains deferred. The first connected Downloads implementation (#55 → #56 → #57) is qualified by [source-bound native evidence](validation/connected-downloads.md), including existing-flow regression. Qualified slices #58/#59 cover mixed-location/access/overlap and structured inspector evidence; original full parent parity remains open. Failed access remains unknown coverage after its old scan is retired; remembered included locations without current observations prevent a complete-coverage claim. Omitted locations do not contribute current coverage, and re-inclusion requires a fresh manual check. Locations labels remembered ancestor/descendant overlap without removing configuration or summing shared storage twice. At compact widths, shared recovery actions move below identity/status to keep their labels readable. Successful access renewal retires that location's obsolete access notice; other included locations retain their own current failures. The Explorer inspector separates observed location/scope/time and sizes, why listed, cleanup action/consequence and specific protection/unavailable reasons; inspection never selects or authorizes cleanup. Protected file-type/location explanations come from the same canonical policy that excludes those paths, without changing eligibility. Native qualification of these #58/#59 additions is recorded separately in [connected next-slice evidence](validation/connected-next.md).

Integrated checkpoint `03cbdfc` delivers #60 (caller-aware recovery under #48), #61 (truthful terminal Results under #50), and #63 (optional folder-access education under #46). Manual recovery returns to its real caller; startup recovery returns Overview. Current observed caller viewport and live session context remain process-owned, separate from durable facts. Terminal presentation distinguishes applied, partial, no-op and unresolved outcomes without claiming released space. Unknown outcomes require recovery review instead of ordinary retry. Existing exact unfinished-file recheck/new-approval and explicit new-plan boundaries remain. #63 adds optional folder-access education in Locations, using a restrained disclosure with no inferred Full Disk Access status, OS prompt, discovery scan or cleanup-policy expansion. #62 is integrated at `03779f5`, sharing existing Local records management from History and Locations; it retains current maintenance safeguards and future diagnostics/exclusion gates. Local records has one Back to its History/Locations caller; recovery entered there returns to that page, while gated diagnostics returns directly to the root caller as locked in Q17. [Local records qualification](validation/local-records.md) tracks this slice. [Recovery/results qualification](validation/recovery-results.md) records implementation and native evidence separately from requirements; full parent acceptance, unresolved History/appearance decisions and future milestones remain preserved.

Every implementation slice must name parity and FL IDs, synchronize **SPEC and DESIGN-HANDOFF**, cover the complete user journey and its exceptional states, and retain explicit proof limits. Design annotations precede implementation; original native Light/Dark initial/minimum capture and public-flow verification precede UI merge. A helper, probe, inaccessible development route or successful build alone is not feature completion.

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
- Eventual direct Developer ID distribution, Hardened Runtime and notarization belong to M8 — Commercialization (#40). Distribution signing and preflight do not gate ordinary feature implementation or local fixture testing. Development retains normal ad-hoc signing where required. Initially unsandboxed, logged-in user privileges only; no root helper.
- Foundation metadata/file operations; bounded background I/O. Swift concurrency for orchestration; never block MainActor or create a task per file.
- SQLite behind a repository with migrations, one writer and batched writes.
- Swift Testing for policies/fixtures; XCTest UI tests for key journeys.

Pipeline: scoped metadata discovery → observations → versioned classification rules → findings → mutable plan draft → approved immutable plan → revalidation/executor → journal/results. Only the executor may mutate cleanup targets. The capacity monitor cannot invoke the scanner or executor.

Core types: ScanScope, ScanSession, FileObservation, StorageSnapshot, Finding, PlanDraft, CleanupPlan, ActionRecord, AlertPreferences and AlertEpisode. Preserve resource identities, scope/rule versions, timestamps and completeness rather than passing bare paths/byte totals between layers.

## Overview findings contract

Overview follows startup-volume capacity → scanned-locations evidence / Explore storage → Recommended for review. The shared bordered group always accounts for downloaded iCloud files, developer build files, Downloads and browser caches; unavailable or uninspected categories explain their state rather than displaying invented zero-byte findings. Only actual observed evidence supplies amounts. Cloud allocation belongs to the currently inspected location and remains Unknown when cloud membership or state is unknown, even if the identified local subtotal is zero; Downloads review counts use model-owned eligibility across explicitly scanned Downloads locations, independent of a retry subset. Logical file size is not promised released space. Whole-scope unknown totals stay unknown and overlapping scopes are never naively summed.

Explore storage opens existing inspection. During a targeted retry, Overview describes the observed Downloads findings and offers an explicit Scan again to review all files action. This new manual scan ends retry filtering, rechecks the known locations, keeps unchanged chosen files and leaves newly discovered files unchecked; it does not approve any action. The ordinary Review files action remains inspection only. Downloads Review files opens the included observed Downloads category view across scanned locations, including after focus moved elsewhere, without selecting or redirecting to the plan. Merge repeated directory-entry observations without collapsing distinct hardlink targets; retain explicit limited coverage. Existing cloud evidence expands read-only; this does not enable eviction. Developer/browser cleanup remains gated. Scan again sequentially rechecks all known explicitly chosen locations without another chooser, keeps review blocked throughout, preserves unchanged selections and restores the previously focused location when finished. A fixed footer keeps Stop scan reachable while reading lower findings. Stop cancels the queue; a new scan cannot be overwritten by a cancelled generation. Unknown, excluded, partial and interrupted coverage remain explicit. The direct folder/Downloads chooser remains near the coverage summary. Future tools stay secondary below findings. Alerts and interrupted cleanup retain their contextual notices.

## Selection and navigation contract

There is one live, session-only PlanDraft keyed by the exact observed directory-entry path, resource identity and action. Every checkbox in every view updates it immediately. Repeated appearances of the same entry share membership and count once. Distinct hardlink directory entries remain distinct exact targets; choosing one never silently substitutes its alias. Storage-byte totals deduplicate shared resource identities, separately from the selected path count. File names inspect; folder names enter their observed folder, with a separate folder-info inspection action. Neither changes selection. Back and Cancel preserve selections. The item-review CTA is “View cleanup plan”; there is no staged apply step or inspector exclusion control.

Category selection materializes exact eligible IDs from the current scan. Downloads has the same unchecked/mixed/checked control, labelled with eligible count and bytes. It selects ordinary files, including ZIPs, PDFs, videos and installers within the scanned Downloads tree. It never targets the Downloads folder or other directories. Protected packages, managed libraries and unavailable files remain excluded. Show relative paths for nested files; record original and resulting Trash locations, without promising preserved directory structure or automatic restoration.

Selections persist across navigation and window closure while the process runs. Explicit Quit ends the unexecuted plan; next launch requires a fresh scan. Preferences, completed history and unresolved recovery records persist independently. No saved draft authorizes mutation.

A rescan retains selected identities as pending choices and suspends execution. On completion, revalidate retained targets, explain removed/changed targets and leave new discoveries unchecked. On cancellation keep choices visible with “Refresh required”; partial observations never make the old plan executable. Permission or volume changes similarly suspend affected choices. Execution performs its own fresh checks.

“Review cleanup” opens a summary with count, scope, total size, action/consequence and expandable exact targets. One explicit final approval freezes an immutable plan; no second per-file approval is required. Skip changed/unavailable targets and continue unaffected approved targets. Never replace targets, expand scope or change action without a new approval. Starting execution consumes the plan; unresolved items require recheck and new approval, not automatic repetition.

## Filesystem correctness

Directory identity/modification evidence is checked around enumeration. One changed pass may receive one whole-scope recheck within the same 100,000-entry budget and cooperative 30-second deadline. Repeated instability or exhausted bounds is partial coverage, never a growth baseline. Root identity remains pinned across both attempts. Blocked OS calls still need to return; this is not an atomic snapshot. See [directory-stability validation](validation/directory-stability.md).

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

Alert defaults: 40 GB suggested threshold, decimal units, valid range at least 1 GB and below volume capacity. Sample roughly every 15 minutes while awake plus coalesced activation/wake. One notification per low episode; rearm at threshold + 5 GB capped at capacity. Snooze is 24 hours, with one low-space reminder after resumption. Persist suppression across launches and preference changes. Missing capacity pauses decisions. Opening an alert opens Overview with the original alert observation time, clearly separate from current startup-volume capacity, and offers an explicit folder choice for a fresh scan; it never starts one. Legacy or malformed alert timestamps show time unavailable rather than an invented observation. The detailed technical spec defines failure and metric-change handling.

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

## Native recovery evidence boundary (#12)

Startup recovery reads existing local durable records without mutating cleanup state or inspecting target paths. Pending remains not started; intent/unknown remains unresolved, including when an original is missing. Recorded terminal outcomes remain historical facts. Reading recovery restores no session choices, file permission or approval, and never executes/retries. See [actual crash-boundary evidence](validation/startup-recovery.md).

M4 implementation evidence: [compatible aggregate comparisons](validation/growth-comparisons.md). This remains future-gated, uses explicit manual scope observations and bounded aggregate-only history, and keeps unresolved cleanup journals outside retention/clearing authority.

M6 diagnostics implementation accepts only allowlisted versions, aggregate session/scan counts and fixed status/error codes. The explicit review snapshot is immutable through native Save cancellation or write failure; saving writes exactly the previewed JSON locally and neither uploads nor changes recovery authority. Known local app-state destinations and their symlink aliases are refused; unavailable state protection fails closed. Private paths, names, identifiers, raw errors and contents never enter the payload. The route remains behind the future-milestone development flag pending M6 qualification.

M6 explicit custom exclusion semantics are defined in [EXCLUSIONS.md](EXCLUSIONS.md): volume-bound canonical path rules reduce included scan/candidate coverage, never arise from deselection, preserve immutable safety protections and require fresh findings after changes. This contract precedes implementation.

## Current-build cleanup scope guidance

> Historical implementation record at f9e854f. The approved [flow lock](FLOW-LOCK.md) supersedes the global plan banner/chooser and detour below: use contextual category prerequisites and stay on the initiating screen. Preserve Downloads-only safety while implementing the approved replacement; do not copy this old composition into new screens.

Overview before scanning, folder inspection and Cleanup plan display: “Cleanup currently supports files in Downloads only. Other folders are inspection only.” A shared “Choose Downloads…” button opens the native folder chooser at the user's Downloads directory. Scanning begins only after the user confirms a folder; Cancel preserves the current view, observations and choices. The chooser permits another location for inspection and repeats the restriction. The shortcut does not grant eligibility, select files or approve cleanup. It is disabled during scanning/selection preparation where applicable; execution retains its dedicated progress flow. Files inside Downloads remain subject to all existing completeness, identity and protection checks. Broader ordinary-file cleanup and whole-folder cleanup require separate product/safety design; this guidance does not expand M1 mutation scope.

### Narrow pip inventory support (#24)

The future-gated pip route can inspect an explicitly selected cache using Apple Command Line Tools Python 3.9 and its bundled pip 21.2.4 only. Before Python execution, verify Apple signatures for the fixed interpreter and framework and the pinned bundled-wheel digest. Run the bundled wheel with isolated Python and site initialization disabled; never execute arbitrary selected interpreters or installed site packages. No setup, package installation, network command, cleanup or default personal cache discovery is allowed.

`--cache-dir` deliberately overrides user configuration for this inspection; show the tool-reported resolved root and observation time. A bounded metadata preflight rejects cache links and incomplete/unreadable traversal before vendor commands. Show listed-wheel logical/allocated subtotals separately from vendor text and unknown total-cache allocation; HTTP-v2 and other modern contents remain unmeasured by this legacy tool. Shared allocations are not exclusive reclaimable bytes. Timeouts, missing developer tools, changed signatures/digest or unsupported output leave guidance without cleanup authority. This does not qualify pip mutation (#25), newer versions or arbitrary installations.

### Docker read-only inventory (#33)

The future-milestones Docker route can explicitly inspect an existing local Unix socket using the unmodified official Docker **28.5.1 static macOS CLI** (arm64 or x86_64) with Engine **28.5.1**. A matching executable hash is required before a private staged copy is executed; basename/version claims alone are not trusted. Docker Desktop bundled clients and other releases remain unsupported. No default endpoint/context, personal Docker configuration, remote transport, installation, daemon startup, elevation or mutation is used. The only runtime operations are `version --format '{{json .}}'` and `system df --format json`, with an empty private config and bounded execution/output. Unsupported, missing/denied socket, timeout and malformed report states retain guidance rather than inferred measurements.

Editing the explicitly entered socket invalidates previous daemon report/provenance immediately and requires another explicit inspection; independent selected-image metadata is preserved. Reassigning an identical path leaves evidence intact.

Daemon categories are Images, Containers, Local Volumes and Build Cache; persistent volumes remain explicitly labelled application data. Daemon sizes/reclaimable estimates are display evidence, not exclusively releasable host bytes. Explicitly selected host-file metadata remains separate from daemon output and does not establish Docker ownership or VM virtual capacity. Genuine disposable CLI/Engine integration is not yet qualified; the future route states that limit and offers no cleanup action. See [Docker validation](validation/docker-inventory.md) for exact provenance and remaining gates.

### Homebrew cache-only inspection (#22)

The future-gated Homebrew page requires an explicitly selected `bin/brew` and cache folder. Support is limited to the exact official Homebrew 4.6.17 shell bytes for `bin/brew`, `brew.sh`, `help.sh` and `formula_path.sh`. The version label means **pinned shell-source provenance**, not qualification of the whole installation, its Ruby, packages or configuration. Changed/unknown source produces guidance before cache traversal; selected installed code is never executed.

Only verified in-memory source bytes are copied into an owned temporary staging directory. Apple `/bin/bash -p` runs the staged `brew.sh` shell fast paths for the exact argument `--prefix` or `--cache`. Both return before Git, wrappers or Ruby. The installation prefix comes from the selected executable layout; cache is an explicit override, not discovered configuration. No `brew.env`, user shell configuration, taps/formulae, package receipts, installed Ruby, auto-update, downloads or analytics are loaded. The app never provisions a tool. Temporary staging is removed after the query.

A bounded metadata inventory reports regular-file count, download-file count, top-level `.incomplete` observations (at most 100 retained / 20 displayed), and logical/allocated totals deduplicated by device/inode. Symlinks, other volumes, dataless entries, traversal errors, overflow or changed root identity/mtime produce partial coverage and unknown totals. Enumeration stops at 100,000 entries, depth 64 or a cooperative five-second deadline. Metadata is not an atomic snapshot. Missing/denied roots, query timeout/output limits and unknown output retain guidance. Choosing a new source/cache clears old evidence; Cancel preserves it. No automatic scan occurs.

Incomplete names may belong to active downloads; arbitrary chosen folder ownership is unproven. Observed allocated bytes are not exclusive reclaimable space. No age, obsolete-package, formula/Cellar cleanup or vendor `brew cleanup` eligibility is inferred. Reclaimable space remains unknown and no item enters the cleanup plan. Full vendor preview and mutation (#23) stay gated: genuine cold `brew --version` writes Git describe-cache state, and cleanup can load mutable package Ruby. See [Homebrew qualification](validation/homebrew-preview.md).

### M5 monitoring lifecycle implementation

The production monitoring controller and native system adapter share the [controlled orchestration contract](validation/alert-monitoring-orchestration.md). Renewed enablement owns its authorization/sample work independently of obsolete generations; an observed invalid threshold stops polling. Accepted Quit makes that controller session terminal for activation, wake and delayed work while preserving saved intent for a fresh process. Ordinary disable and reset remain resumable. Per-submission cancellation identities are saved with notification intent before OS submission and recovered on restart; obsolete completion cannot remove a newer request. Older saved episode records retain suppression when this optional ownership metadata is absent. Editing the threshold does not change monitoring until Apply; invalid or unapplied text leaves the last applied threshold active. These are feature lifecycle rules, independent of M8 signing/distribution. Real OS authorization/delivery and login approval remain separately qualified.


## Locked startup capacity refresh — #49

Current Overview/sidebar capacity is implemented as one process-owned reading. Launch, manual refresh, alert opening, logical scan/recheck completion or stop/failure, and cleanup completion request startup-volume metadata; foreground activation uses the 30-second freshness rule. Overlap coalesces while preserving a trailing post-action read, and a 10-second logical expiry ignores late replies. This adds no polling, keepalive, scan, permission request or alert-policy change. Current display, scan-scope inventory, alert context and immutable operation measurements remain distinct.

Failure retains explicitly last-observed evidence or shows unavailable; it never fabricates zero. Valid available space without a usable total remains visible with no filled meter. The shared card offers Refresh capacity/Try again separately from Scan again. [Canonical contract](CAPACITY-REFRESH.md) and [bounded qualification](validation/capacity-refresh.md) record implementation and combined native proof at final presentation source `8869b38`; all 71 final original captures have been individually reviewed and accepted. This does not certify all OS/CPU/provider/accessibility behavior or advance M5/M8.
