> Historical revision 0.8 reference. Preserve feature detail, but implementation scope and interaction rules are superseded by [SPEC](../SPEC.md), [design handoff](../DESIGN-HANDOFF.md), and [milestones](../MILESTONES.md), revision 0.9. In particular, staged item drafts, clearing selections on rescan, persistent plans and installer-only selection are obsolete.

# macOS Storage Companion — Preliminary PRD

Version 0.8 • October 22, 2026 • Working name, not a branding decision

Status: proposal for a personal-first macOS application, with a path to a commercial release. Scope and targets are preliminary. Companion: [Technical specification](macos-cleaner-technical-spec.md). Background: [Storage research](macos-cleaner-research.md), [Competitor research](macos-cleaner-competitors.md).

## Product decision

Build a native, local-first macOS storage application that answers:

1. What occupies local space?
2. What grew since my last scan?
3. What can I remove or offload, and what will happen?
4. How much capacity became available, and did the benefit persist?

Default operation is on demand. Optional Storage Alerts are included in v1, disabled initially. When enabled, Still remains in the menu bar after its window closes and periodically checks available capacity only. Explicit Quit stops all monitoring once active operations reach a safe boundary. Start at Login is a separate opt-in; Quit does not change that saved preference. No automatic deletion or unattended folder scanning occurs.

## Problem and audience

Primary user: a person with a 256–512 GB Mac who uses iCloud yet repeatedly encounters storage pressure. They need to preserve personal files and understand cloud versus local storage. Secondary user: a developer whose tools generate build artifacts, downloaded packages, simulators and container data.

Current alternatives offer capable maps and cleanup actions. We should match essential usability and pursue better growth diagnosis and consequence-aware planning. These are product hypotheses, not proven market gaps. CleanMyMac already provides cloud unsync, and Mole provides developer cleanup; see the competitor report for supporting sources.

## Outcomes and principles

- Useful inspection without requiring broad disk access.
- Every recommendation explains its evidence and consequences.
- Local cloud eviction is visibly distinct from synchronized deletion.
- “Old,” “large,” “hidden,” and “System Data” never independently authorize cleanup.
- Estimates, moved-to-Trash bytes and observed capacity changes are separate measures.
- No account, server, cloud credentials or AI service is required for the MVP.
- A permission denial is a supported operating mode, with honest scan coverage.

## MVP scope

| Area | Requirement | Acceptance condition |
|---|---|---|
| Scoped scanning | Scan user-selected folders and explicitly enabled known locations. Progressive results, cancellation and exclusions. | User can inspect a selected folder without Full Disk Access; denied paths are listed without claiming whole-disk coverage. |
| Overview | Largest-first file/folder list; grouping by location and recognized app/category; available capacity and last scan time. | Every aggregate indicates completeness and size meaning. Unknown owners remain unknown. |
| Inspection | Quick Look, Reveal in Finder, path, apparent size, allocated size where available, modified time and rule evidence. | Preview of a cloud-only item requires an explicit download decision. |
| Growth | Compare two compatible completed scans at category/folder level. | First scan establishes a baseline; changed scope/permissions generate a warning and are not misreported as growth. |
| Findings | Review large Downloads/installers; inventory local device backups and major app data; recognize a small set of reproducible developer caches. | Findings distinguish personal data, rebuildable data, cloud downloads and system-managed storage. |
| Plan | User explicitly selects eligible category targets or individual items in Cleanup Plan. Group confirmation by action and consequence, with expandable file lists. No cleanup space-target control. | Nothing is preselected. Available-space estimates exclude Trash-held bytes. Inspection and selection are distinct interactions. |
| Browser caches | Optional recommendation grouped by browser and identifiable profile/cache group. Permanently clear only recognized cached files after the browser is closed. | Nothing preselected. Logins, cookies, website/offline data, history, passwords, autofill, downloads and session/tab state excluded. Recheck before execution; skip running browsers. |
| Storage alerts | Optional available-capacity threshold alerts and independent Start at Login setting. | Disabled initially; monitoring checks capacity only. Notifications require user authorization; no repeated alert during the same low-space episode. |
| Actions | Move selected ordinary files to Trash; offer local-only iCloud eviction after validation; use supported native tools for approved cache adapters. | Every action has a preview, revalidation and per-item outcome. Permanent tool cleanup is explicitly identified before execution. |
| History | Local action records and category-level scan snapshots. | Show planned estimate, successful/failed/skipped actions, Trash retention and observed capacity change separately. |
| Guidance | Explain Photos optimization, Finder device backup management and macOS-managed snapshots. | App-managed libraries are not modified internally. |

Read-only inventory of a location does not imply a supported deletion action. App uninstall, duplicate detection, direct backup deletion and automatic cleanup are deferred.

Initial browser shortlist: Chrome and Safari only, gated independently by tested OS/browser versions and permission behavior. Unsupported or uncertain cache groups get guided native-browser cleanup rather than a direct action. Safari profile boundaries must be established before claiming profile-level cleanup; shared/unknown groups are explicitly labeled. Other browsers are deferred.

Initial adapter shortlist: Xcode DerivedData inspection/cleanup, Homebrew cleanup preview, and pip cache inventory/cleanup. Each ships only after fixtures and real version-specific behavior pass validation. Docker inventory may be included; Docker mutation is deferred because volumes and stopped-container data require more specialized review. Missing tools are skipped without installing anything.

## User experience

### First launch

1. Present a short promise: understand local storage and review actions before changing files.
2. Offer **Choose folders** and **Inspect common locations**. Explain scope before filesystem access triggers system prompts.
3. Run a read-only scan and show incremental findings.
4. If relevant areas are denied, show **Expand coverage** with an explanation of broader access. Continue with existing results.
5. Introduce cleanup only after there is something concrete to review. Introduce notifications/background monitoring only if the user enables those later.

Example folder-access explanation: “Inspect sizes and metadata in folders you choose. Files are changed only when you approve a cleanup action.”

Example broader-access explanation: “Full Disk Access can let this app inspect sensitive data, including Mail and Messages. It improves coverage of protected app data. You can continue with a limited scan.” Do not imply the OS grant itself is read-only; the app's scan policy is read-only.

### Navigation

- **Overview:** capacity, scan coverage, biggest owners/locations and recommended next steps.
- **What Grew:** differences between scans, with scope and timestamps.
- **Cleanup Plan:** choose macro categories directly, optionally refine exact items inline, then review consequences and estimated benefit.
- **History:** action results and prior category-level observations.

Settings contain Scan locations & access, Storage alerts, exclusions, history retention and data reset. The four primary sidebar destinations remain unchanged; Storage alerts is a secondary settings destination. An accessible list is primary; a treemap is a later enhancement.

### Recommendation card

Each recommendation shows its category, estimated bytes, action and one short consequence. The inspector exposes owner/location, evidence/rule version, size meaning, confidence, offline and rebuild costs, reversibility and exclusion reasons. Avoid repeating every field on every card.

Illustrative example: “Xcode build data — generated artifacts from selected projects. Rebuilt from source; next build may take longer. Release archives excluded.” Numbers are supplied by actual inventory, not generic promises.

### Execute and recover

Freeze a versioned plan at approval, revalidate targets, execute serially initially, and record results individually. Changed or inaccessible items are skipped. Cancel stops new operations; an operation already underway completes or reports its failure. Do not claim transactional rollback across multiple files/tools.

For ordinary files, record the resulting Trash location and offer Reveal in Trash. Finder restoration is the MVP recovery path. Explain that Trash does not free space until emptied; do not empty the entire Trash as a side effect. Tool purges and cloud eviction have their own recovery semantics and are labeled separately.

## Browser caches — v1

Add **Browser caches** under Overview recommendations, not a new permanent sidebar destination. Summary: “Clear cached files. Keep logins and history.” Show estimated cache bytes and any running/inaccessible-browser qualification. Discovery is user-requested and read-only; the alert monitor never scans browser storage.

The review screen groups detected cache allocations by browser and reliably identified profile. Show a clear browser status: closed/ready, running/close first, access denied or unsupported version. Nothing is selected initially. If profile mapping is uncertain, label a shared cache group instead of fabricating ownership or double-counting it. No browser-account identifiers or browsing contents are displayed.

Only cached images/files and other verified recreatable asset caches are eligible. Exclude cookies, site storage (including IndexedDB, Local Storage, service-worker/offline data), passwords, history, autofill, download records, downloaded files, sessions and open-tab state. Browser binaries and whole profiles are never targets.

Running-browser flow: ask the user to close the browser, offer **Rescan [browser]**, then enable only freshly validated groups. Do not force-quit, automate quitting or require Accessibility. Helpers/background processes and active writes must also be considered; uncertainty means skip or provide guidance.

Eligible browser groups can be selected directly through Cleanup Plan’s Browser caches category and its inline profile list, or added from detailed browser review. Confirmation uses **Clear browser caches**. Confirmation states permanent removal, protected data and expected cache regrowth/slower initial page loading. Revalidate browser activity, rules, target identities and access immediately before each group. A reopened browser is skipped. Results show cleared/skipped/failed bytes separately and offer **Review browser caches** for a fresh check; never blindly replay successful actions.

Cache removal is temporary space relief, not a general performance improvement. Recovery is regeneration/redownload, not an Undo promise. Any detected access restriction follows the existing permission model; do not ask for all browser data access on first launch or imply Full Disk Access is always necessary or sufficient.

## Storage alerts and background behavior

Storage Alerts replace the earlier cleanup space goal. They answer “when should I review storage?”, not “delete enough files to reach a target.” They are an optional v1 feature, off by default.

| Setting or state | Required behavior |
|---|---|
| Alert threshold | “Notify me when available space falls below [40] GB.” 40 GB is an editable example/default suggestion, not an OS requirement. Valid values: at least 1 GB and below volume capacity; decimal GB. |
| Enable alerts | Explain background behavior, then request notification authorization in context. Monitoring becomes active only after permission is allowed. If denied, retain the preference as requested but show “Notifications blocked”; do not start an invisible monitor. |
| Start at Login | Independent explicit opt-in, available after alert opt-in. Reflect macOS enabled, approval-required and disabled states. The app never silently registers at login merely because alerts were enabled. |
| Window close | If alerts are active, keep a visible menu-bar presence and capacity checks running. Otherwise stop after active user-requested work ends. |
| Quit Still | Stop monitoring and show that consequence in the menu. The saved Start at Login preference remains unchanged for the next login. |
| Disable alerts | Stop background capacity checks and remove pending threshold notifications. No background work remains solely for alerts. |
| Background workload | Check startup-volume available capacity on activation/wake and approximately every 15 minutes while awake. No recursive scanning, content reads, hashing, cloud hydration, FSEvents watching or cleanup. No wake-from-sleep or exact-timing guarantee. |
| Low-space episode | First eligible reading below the threshold may notify, including the first check after opt-in. Suppress repeats while the episode remains low. Rearm only after a reading reaches threshold + 5 GB (capped at volume capacity). Persist episode state across restarts. |
| Remind me later | Explicit snooze for 24 hours. At expiry, recheck; allow one reminder only if still low. No reminder while sleeping or quit; recheck when running again. |
| Notification click | Open Overview, show measurement time and offer a fresh scan. Never start scanning or cleanup from a notification. |
| Notification content | “Your Mac has 28 GB available. Below your 40 GB threshold. Open Still to review storage.” These are illustrative values. Never imply reclaimable capacity from an old scan. |
| Permission removed | Stop alert-only monitoring; show Notifications blocked when opened. No repeated permission prompts. Focus and OS notification settings control actual presentation. |

Only startup-volume capacity is monitored in v1. Alerts do not require Full Disk Access, folder selection or cloud credentials. Available capacity includes space macOS reports as available; it must not be confused with file-level cleanup estimates. UI displays the reading timestamp and last-check status.

Two manual scans still support net-growth comparisons while the app was closed. Continuous folder tracking and causal process attribution remain outside v1.

## Permissions policy

Request access when the associated feature is used, not as a startup checklist. Selected folders and ordinary user-level access come first. Protected folders, other apps' data and optional Full Disk Access need clear explanations. Optional notifications and login-item registration are separate choices. No Accessibility, Screen Recording, microphone, camera, contacts, Apple Account credentials or administrator helper is required by the proposed MVP.

The technical spec distinguishes App Sandbox, privacy permissions and Unix ownership; they are separate controls. Full Disk Access is powerful and does not bypass every restriction. Protected system data and other users' private files remain outside our cleanup scope.

## Privacy and retention

All scanning and cleanup are local. Keep file contents out of the database; metadata/path names are sensitive too. Persist category/folder-level completed scan summaries by default, with a rolling 90-day retention and at most 30 baseline snapshots. Detailed per-file scan data is session-only unless explicitly enabled later. A completed baseline may store larger recognized folder IDs/paths necessary for growth comparison.

Store minimal path/action records for cleanup history for 90 days, with Clear History and Delete All App Data controls. Bound database size to a proposed 250 MB target; compact and evict old history at the limit. Diagnostics export is user-initiated, previewable and redacts home paths by default. No telemetry is required; any later diagnostics collection is separately designed and opt-in.

## Non-goals

- Cleanup space-target control, continuous folder monitoring and automatic growth notifications in v1.

- Antivirus, RAM optimization, fan controls, startup tuning or generalized “speed boost.”
- Blanket removal of System Data, snapshots, swap, Application Support or orphaned containers.
- Modifying Photos/Mail/Messages databases, application binaries or signed bundles.
- Automatic cloud-wide deletion, cloud-account inventory, cloud login or cross-device management.
- APFS clone consolidation, whole-volume exact exclusive-block accounting, root daemon or system extension.
- Automatic scheduled deletion, plugin marketplace or remotely executable cleanup rules.

## Success and release gates

Safety gates: no writes during discovery; no unapproved targets; changed identities skipped; no cloud hydration caused by routine metadata scanning; synchronized deletion unavailable in the local-eviction action; denied access reported accurately. Cancellation and partial failures must leave usable history.

Correctness gates: hard links, clones, sparse files, cloud placeholders, packages, symlinks and partial scans have explicit accounting behavior. Growth comparisons distinguish lost coverage from actual deletion. Supported cleanup rules pass their own fixtures and version checks.

Proposed usability target: at least 4 of 5 pilot users can identify the largest actionable category and correctly explain its consequences without help. No claim of market validation until measured.

Performance targets, to validate on a fixed 512 GB Apple-silicon reference Mac and one-million-entry synthetic tree: first progressive results within 3 seconds after scope access; cancel acknowledged within 1 second; UI remains interactive; peak scan memory below 300 MB. Completion time is reported, not promised universally. Optional capacity monitoring targets under 0.5% of one CPU core on average and under 75 MB incremental memory under a defined idle test.

Product metric: capacity still available 7 days after a cleanup, with background-work caveats—not cumulative deleted bytes. Track time to useful finding and whether users understand local versus cloud effects. Measure locally during pilot unless participants explicitly consent to sharing.

## Delivery stages

1. **Feasibility:** access model, cloud metadata/eviction, safe Trash operations, allocated sizing and scan fixtures. No destructive real-data experiments.
2. **Read-only alpha:** Overview, common-location inventory, growth baselines and coverage reporting.
3. **Cleanup beta:** versioned plans, Trash, validated iCloud local eviction, limited adapters and history.
4. **Storage alerts beta:** explicit opt-in, notification/login states, capacity checks, episode suppression, snooze, menu-bar lifecycle and permission revocation tests.
5. **Personal v1:** signed/notarized build, release tests, recovery guidance and performance validation. Folder-event monitoring stays deferred.

No calendar estimate is committed before the feasibility stage. A native macOS app is the selected direction; distribution, OS support and exact adapters remain provisional decisions detailed in the technical spec.

## Design synchronization — revision 0.8

Canonical interactive design: `storage-companion-direct.html` (conversation preview; sample data and simulated OS permissions). See [Design/spec contract](macos-cleaner-design-contract.md) for the shared defaults and acceptance matrix. Earlier design iterations are historical.

The current design also specifies a scoped storage browser with a wider inspector; checkbox selection distinct from item inspection; consequence-first grouped confirmation; progress/cancellation; separate Trash totals; targeted rescanning of skipped items; first-baseline and changed-coverage comparison states. These are MVP requirements. The preview is not an implementation of native file operations or system permissions.

### UI refinement — revision 0.8

Overview separates potentially releasable estimates from Trash-held allocations and qualifies eligibility. App-managed storage guidance remains secondary to actionable findings. Manual scan location copy includes recognized caches. See [UI handoff review](macos-cleaner-ui-handoff-review.md) for explicit design coverage and remaining v1 flows; these gaps do not remove existing requirements.

### Empty and blocked state requirements — revision 0.8

The [UI state contract](macos-cleaner-ui-state-matrix.md) is the shared acceptance reference for SCAN, ACCESS, CAP, PLAN, HIST, FILES, CACHE, CLOUD and RESULT states. Discovery scopes include an explicit recognized-browser-caches choice. Empty states explain how to proceed; blocked states name the affected location/group and preserve unaffected work. No scan selection is cleanup consent. Completed results reflect selected accessible coverage, and require another compatible completed scan before reporting growth. Unknown storage is not zero.

## Window stability — revision 0.8

Screen changes, scan states, disclosures and permission messages must not resize or reposition the app window. The user controls resizing. Preserve scroll, focus and selection across incremental updates. Follow the [window and interaction stability contract](macos-cleaner-layout-contract.md).

## Direct planning flow — revision 0.8

Cleanup Plan remains useful with zero selections: show category checkboxes, eligible counts/sizes, inline item/profile disclosures and a disabled Review cleanup button. Reserve a full empty state for no completed scan or no eligible findings. Categories select exact eligible targets from the current scan; partial selections show mixed state. A rescan never silently extends a prior selection. Scan again uses existing locations directly; scope editing remains in settings. A finished cleanup invalidates the old general plan, while a targeted retry reviews only newly revalidated skipped targets. See the [flow audit](macos-cleaner-flow-audit.md).

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.
