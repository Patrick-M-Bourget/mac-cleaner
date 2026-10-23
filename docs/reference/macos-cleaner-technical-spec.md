# macOS Storage Companion — Preliminary Technical Specification

Version 0.8 • October 22, 2026 • Proposed architecture, not implemented

Companion: [PRD](macos-cleaner-prd.md). API behavior and distribution choices require feasibility testing on supported macOS versions.

## Recommended stack

| Layer | Selection | Rationale |
|---|---|---|
| Language/build | Swift 6 language mode; Xcode; Swift Package Manager for internal modules | Direct access to macOS APIs, compile-time concurrency checks and native distribution. |
| UI | SwiftUI app shell and screens; AppKit interop as needed | Native navigation, accessibility and settings; mature folder panels, Finder integration and large-table fallback. |
| Scan execution | Swift concurrency; bounded worker tasks and actors; blocking filesystem calls kept off MainActor | Progressive output with limited memory and responsive cancellation. |
| Filesystem | Foundation URL/FileManager resource APIs; focused Darwin calls behind one abstraction where justified | Metadata enumeration and native Trash/eviction; no recursive shell deletion. |
| Storage | SQLite through SQLite3 behind a small repository; explicit migrations, batched transactions and one writer | Predictable incremental queries and bounded local history. Revisit a thin wrapper if direct bindings become noisy. |
| Integrations | Versioned, compiled Swift adapters; Foundation Process with executable URL and argument arrays | Native tool semantics, explicit previews and timeouts; no shell interpolation. |
| Storage alerts, optional v1 | ServiceManagement/SMAppService, UserNotifications and MenuBarExtra | Capacity-only checks and explicit opt-in. FSEvents-based folder monitoring is deferred. |
| Testing | Swift Testing for core policies/fixtures; XCTest UI tests for critical flows | Protect filesystem correctness and permission-dependent behavior. |

SwiftUI and AppKit are designed to interoperate. Choosing them is an engineering judgment, not a platform requirement. Electron/Tauri could provide a UI, but would still need native filesystem, privacy, cloud and service-management integrations; a web stack offers little benefit for this macOS-only product. [Apple: SwiftUI/AppKit integration](https://developer.apple.com/videos/play/wwdc2026/272/)

Provisional support: macOS 14+, Apple silicon first. Keep the core portable to Intel and produce a universal build only after Intel testing is available. Test the oldest supported version and each subsequently supported major release. Newest-SDK API use must be availability-guarded.

## Distribution and privilege decision

Start with a directly distributed, Developer ID-signed and notarized app, with Hardened Runtime enabled and App Sandbox disabled for the initial broad-inspection build. Run as the logged-in user. No root daemon, privileged helper or request to disable platform protections.

This simplifies supported external CLI integrations and broad user-level scanning, but does not remove privacy, ownership or system protection boundaries. Mac App Store distribution requires App Sandbox; direct notarized distribution permits optionally enabling it. A later sandboxed edition would need a separately tested scope and reduced adapter surface—not merely a packaging toggle. [Apple: distribution configuration](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution)

Sign all shipped executables, notarize the deliverable and staple the ticket. Notarization checks malicious components and signing; it is not App Review or proof of cleanup safety. Keep a stable bundle/signing identity to avoid unnecessary permission churn. MVP updates can be manual signed releases; evaluate a mature signed updater before public automatic updates. [Apple: notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Modules and boundaries

```text
SwiftUI/AppKit views
    → ApplicationCoordinator
        → AccessManager
        → ScanEngine → MetadataReader → filesystem
        → SnapshotRepository → SQLite
        → DiffEngine
        → RuleEngine → typed Findings
        → PlanBuilder → immutable CleanupPlan
        → ActionExecutor → revalidation → native API / approved tool adapter
        → ActionJournal
        → CapacityMonitor → AlertEpisodePolicy → NotificationCoordinator
        → LoginItemCoordinator
```

Discovery produces observations and cannot mutate targets. Rules interpret observations but cannot execute. Plans identify exact actions and evidence. Only the executor mutates approved targets. UI receives progress/value types rather than filesystem handles. Keep all operations scoped to a user-selected or explicitly enabled root.

The initial single app process is sufficient. A scan actor serializes orchestration; bounded background workers perform metadata I/O. Actors alone do not make synchronous filesystem I/O nonblocking—use a dedicated bounded queue/executor for blocking calls. Batch UI updates rather than publishing every entry. Avoid one task per file.

## Data model

- **ScanScope:** persistent ID, root bookmark/path, volume identity, exclusions, access state and configuration revision.
- **ScanSession:** start/end, OS/app/rule version, scope fingerprint, completed/partial/cancelled state, errors and coverage.
- **FileObservation:** volume/file identity where available, relative path, type, package/link status, logical/allocated bytes, modification data, cloud state and owner evidence. Transient by default.
- **StorageSnapshot:** compatible-scope category/folder totals, observation times and completeness. This is app metadata, not an APFS snapshot.
- **Finding:** classification, matched rule/version, evidence, confidence, consequence, estimated benefit and available action.
- **CleanupPlan:** immutable ID/revision, target identities, explicit action types, preconditions, expected effects and approval record.
- **AlertPreferences:** requested/enabled state, thresholdBytes, startup volume identity, Start at Login intent and observed notification/login authorization states.
- **AlertEpisode:** armed/below-threshold state, lastSubmittedAt, snoozedUntil, pendingReminder, lastSuccessfulSample and nextEligibleCheck. Persist suppression independently of scan history.
- **ActionRecord:** pending/started/succeeded/failed/skipped/unknown outcome, errors, resulting Trash URL if available, observed capacity samples and explanation.

Database contents are private to the app's user and excluded from its own scan. Do not store contents, hashes or cloud credentials in MVP. Paths are sensitive: limit persistence and retention as in the PRD. SQLite is not automatically encrypted; rely initially on macOS account protections and FileVault where enabled, without claiming application-level encryption.

## Scanning and sizing

Enumerate metadata lazily. Request only necessary URL resource keys; avoid opening file contents. Do not follow descendant symlinks, cross volumes unexpectedly or descend into managed library packages without an adapter. Explicitly selected symlink roots require resolved-scope validation. Deduplicate hard links by volume/file identity; a hard link removed while other links remain does not release its shared contents.

Track logical and allocated bytes independently; missing metadata stays unknown. Summing allocations is not an exact exclusive-block measurement for APFS clones or snapshots. Do not promise an exact clone-aware reclaim figure until a validated implementation exists. Volume APIs provide independent free/available observations. [Apple: allocated size](https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey), [APFS](https://developer.apple.com/documentation/foundation/about-apple-file-system)

Scan boundaries are observations over time, not atomically frozen filesystem states. Mark directories that changed during scanning for a bounded rescan; disclose unresolved instability. A failed subtree never silently counts as zero. Cancellation makes partial results viewable but prevents treating them as a complete growth baseline.

Ordinary metadata scanning must not hydrate cloud files. Skip content reads and automatic Quick Look for nonlocal items. Verify this experimentally across target OS versions. A metadata property being available is not sufficient proof of cloud safety.

## Growth comparisons

Compare only completed, compatible scope observations. Preserve additions/removals caused by scope, permission, exclusions, mount changes or classification-rule updates as coverage changes rather than file growth. Show the observation interval and last-complete-scan timestamp.

MVP aggregates folder/category changes; it does not identify which process wrote a file. Exact historical rename attribution is optional. If identities are unavailable, describe path-level changes with reduced confidence. Background monitoring is not required to compute net differences between launches.

## Actions and safety invariants

Supported initial action types:

1. `trashFile`: native `FileManager.trashItem`, saving the returned destination. It can rename the item in Trash. No fallback to permanent deletion if Trash fails. [Apple: Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
2. `evictICloudLocalCopy`: only recognized, locally downloaded iCloud items with validated upload/sync status, appropriate access and no unresolved conflict. Use `evictUbiquitousItem(at:)`, never ordinary deletion. Respect pinning; if pin state cannot be established reliably, defer to Finder rather than silently overriding it. Verify the outcome instead of treating a successful request as immediately recovered capacity. [Apple: eviction](https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:)), [upload validation example](https://developer.apple.com/documentation/xcode/reducing-your-app-s-disk-usage)
3. `runToolCleanup`: narrowly versioned adapter, exact typed scope, preview or adapter-equivalent plan, no automatic installation and no elevation. If current tool semantics cannot be constrained to approved targets, provide guidance instead of an execution button.
4. `clearBrowserCacheGroup`: validated recreatable browser asset caches only; see BrowserCacheAdapter below. Browser must be inactive, with profile/group identity and all exclusions revalidated.
5. `openManagementUI`: supported guidance/launch for backup, Photos, simulator or creative-app management; no unsupported private URL scheme dependence.

Before executing, revalidate root containment, volume identity, file identity/type, symlink ancestry, modification state, owner/access and exclusions. Detect running-owner conflicts where meaningful and skip rather than force-quit apps. Path-string checks alone are insufficient against swaps; sensitive mutations need handle-relative validation where feasible and race fixtures. Block mutations of system paths, app bundles, release archives, backups and user databases unless a separately reviewed explicit action exists.

Journal intent before each operation and outcome after it. On restart, reconcile operations left in “started”; never blindly retry a destructive action. Mark unknown outcomes and provide review. Batch execution is not atomic; report per-item outcomes.

Move-to-Trash and metadata eviction cannot promise instantaneous free space. Record volume measurements before/after and report observed changes with snapshot/background-write caveats. No full-Trash emptying or all-or-nothing rollback promise in MVP.

## Permission matrix

| Access / control | Why it might be needed | Request timing and fallback |
|---|---|---|
| User-selected folders | Inspect and optionally act within chosen locations | Standard folder panel before first scan; inspect only granted scopes. Revalidate persisted bookmarks. |
| Desktop/Documents/Downloads | Direct access to protected user folders | Only when included; provide purpose strings if direct access can trigger prompts. User selection may supply access without a separate prompt. |
| Other applications' data | Inspect cache/support data in protected containers | Only after enabling relevant app-data scanning. Supply `NSAppDataUsageDescription`; handle denial without repeated probing. |
| Full Disk Access | Broader protected-data coverage, such as some backup/Mail/Messages areas | Optional Expand Coverage flow in Privacy & Security. Useful scanning remains available without it. Treat FDA as broad read/write authority, not a read-only grant. |
| Removable/network volumes | Scan an explicitly chosen external scope | Only after selection; handle corresponding privacy restrictions and volume absence. |
| Notifications | Optional capacity-threshold alerts; no growth alerts in v1 | Request when the user enables alerts; use in-app status if denied. |
| Login/background item | Optional monitoring after login | Explicit setting using `SMAppService`; detect disabled/approval-required state and retain on-demand operation. |
| Administrator/root | Systemwide mutations | Not requested in MVP. Skip operations requiring elevation. |
| Accessibility / Automation / Screen Recording | Not needed for native file operations | Not requested. Avoid Finder scripting/UI automation for core cleanup. |
| Photos library authorization / Apple Account login | Not needed for filesystem-level inventory and Photos settings guidance | Not requested in MVP. No Photos content API integration or account login. |

Full Disk Access, App Sandbox entitlements, Unix permissions and System Integrity Protection are distinct. FDA is not an entitlement the app can silently grant itself and does not make protected system files editable. Folder selection also does not erase other restrictions. [Apple: access layers and FDA](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

Usage keys to include only for implemented direct-access flows: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSAppDataUsageDescription`, and volume-purpose strings if those scopes ship. This is not a list of entitlements granting access. [Apple: protected resource categories](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos), [Desktop behavior](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdesktopfolderusagedescription), [app-data description](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppDataUsageDescription)

Apple announced further explicit-user-action controls for FDA on October 2, 2026. Do not predict their exact implementation. Validate permission onboarding on each supported release and avoid relying on a frozen Settings UI flow. [Apple announcement](https://developer.apple.com/news/?id=p6zjojqw)

## BrowserCacheAdapter — v1

Add a compiled, versioned `BrowserCacheAdapter` to discovery, rules and ActionExecutor. Initial candidates are Chrome and Safari; each direct-cleanup adapter ships only after independent validation. A browser being installed does not imply its version/layout is supported. Unknown layouts or inaccessible groups expose native-browser guidance instead of filesystem surgery.

Discovery emits `BrowserCacheGroup`: browser bundle identity/version, OS version, profile identifier/display label where reliably known, shared-group identifier, canonical cache roots, allocated-byte estimate, access state, running/writing state and rule version. Resolve configured roots; never assume every profile is under one fixed path or identify ownership by basename alone. Store opaque profile IDs/local labels, not account addresses or browsing data. Shared groups count once and cannot be offered as separate profile-exclusive savings.

Use a positive allowlist of validated recreatable asset-cache paths. Never remove a whole profile or a whole generic browser-support directory. Explicitly exclude cookies, credentials, history, autofill, IndexedDB, Local Storage, service-worker/offline content, session/tab state and downloaded files. No SQLite vacuum or browser database editing. Enumerate metadata without reading browsing contents; broad cache-directory names alone are insufficient evidence of safety.

Mutation type: `clearBrowserCacheGroup`. The plan records exact roots/identities, browser/profile grouping, rule/version and estimate. Check owning browser and relevant helper/background activity before selection and immediately before each group, revalidate access, symlink ancestry and identity, then clear only permitted cache entries. No app termination or elevation. If reliable inactivity cannot be established or a browser starts/writes during a multi-item operation, stop unstarted entries and report partial completion; check-before-delete is not a guarantee against every concurrent-process race. Prefer supported app mechanisms or native guidance when a layout requires coordination that we cannot establish safely.

This action permanently removes only approved cache entries, explicitly disclosed in confirmation. Future pages recreate/redownload assets. Count candidate allocations separately from observed volume-capacity change and account for failed/skipped groups. A cache result has no Trash/Undo guarantee. Recovery guidance explains regeneration. Activity revalidation and errors use the shared action journal; retry only re-inventoried groups.

No background monitoring, login item, browser automation, Accessibility, passwords or cloud credentials are added for this feature. Access-denied browser containers remain skipped; request broader file permissions only in context and verify behavior on each supported OS version.

Release fixtures: multiple/custom profiles, shared caches, browser/helper running, browser reopening during execution, active writes, unknown browser versions, denied/revoked access, symlink swaps, partial deletion and duplicate discovery. Sentinel files representing every excluded category must remain byte-identical. Validate normal browser relaunch and preserved login/session behavior in disposable profiles on each supported browser/OS combination. Do not test destructive cleanup against the user's personal browser profiles.

## Optional Storage Alerts — v1

This feature replaces the earlier desired-cleanup-space target. It is off by default and independent of foreground scans. Use the existing app process with a visible MenuBarExtra while active; do not add a root daemon or privileged helper. Start at Login uses `SMAppService` and is a separate explicit choice. A later separate per-user agent would require its own permission and IPC design; it is not part of this spec.

### Capacity sampling

Monitor only the startup volume. Use Foundation's important-use available-capacity resource value as the primary available-space metric and share it with Overview. A missing reading is “Unavailable,” never zero. If the primary metric is unsupported, use the documented available-capacity fallback, record the metric kind and reset the alert baseline when that kind changes. Never add purgeable bytes to an already available-capacity reading. Display decimal GB and measurement timestamps.

Take one capacity reading when active monitoring begins, on app activation/wake (coalesce duplicate triggers), and approximately every 15 minutes while awake. Timers are best-effort and may be delayed by macOS. Do not wake the computer, accumulate missed timers or issue catch-up bursts. No recursive scan, file-content access, hashes, FSEvents stream or cleanup runs in response to the timer. Sampling needs no Full Disk Access or selected-folder access. Ordinary scans remain foreground, user-requested operations.

### Alert state machine

- Defaults: alerts off, suggested threshold 40 GB; validate threshold >= 1 GB and < volume capacity. The threshold is user preference, not a system-health rule.
- Separate requested state from effective monitoring state. Effective monitoring requires enabled intent plus notification authorization. Permission denied/revoked stops alert-only polling and sets UI state `notificationsBlocked`. Recheck notification settings when active and before submitting an alert; do not repeatedly prompt.
- `armed` + a valid sample below threshold => submit at most one low-space notification, then enter `belowThreshold`. Initial opt-in can trigger this transition; starting below threshold is not a special failure case.
- `belowThreshold` does not notify again. Rearm only after a valid sample >= min(volumeCapacity, threshold + 5 GB). Persist state, last submission and snooze across launches. Disabling/re-enabling or editing the threshold must not bypass suppression for an ongoing episode; re-evaluate using the saved episode and latest sample.
- Notification submission is not proof the OS displayed it. Track accepted submission, respect Focus/user settings, and do not retry because there is no visible banner. On submission failure, retain a retryable state but rate-limit attempts to the normal sampling cadence.
- “Remind me later” sets a 24-hour snooze and pending explicit reminder. At/after expiry, one valid low reading may submit one reminder. Recovery, disabling alerts or another explicit snooze updates/cancels that intent. Quit/sleep never schedules work outside the running app; recheck after resumption.
- Bad readings, volume identity changes and metric-kind changes invalidate samples; avoid manufacturing threshold crossings. Reset baselines deliberately and preserve already-submitted suppression unless a new volume or genuine recovery justifies a fresh episode.
- On notification open, activate Overview and show sample time; offer a fresh scan. No implicit scan or mutation. Do not claim estimated reclaimable bytes in alert content.

### Lifecycle and permissions

With active alerts, closing the window leaves the menu-bar app running. Explicit Quit stops monitoring and cancels unfinished app-owned notification work, after an in-progress user operation reaches a safe boundary; it does not silently change Start at Login. With alerts off or blocked, no alert-only background process remains. Turning alerts off removes pending threshold requests and stops timers. A saved snooze is passive metadata, not a daemon.

Register the login item only on the user's separate action. Reflect actual `SMAppService` status (`enabled`, `requiresApproval`, `notRegistered` or unavailable) and allow on-demand use if disabled. Do not claim monitoring will resume at login until registration is effective. No automatic change to OS notification settings or Full Disk Access.

Use `UNUserNotificationCenter` to request authorization after the contextual alert opt-in. Register Open Still and Remind Me Later actions. Document permission-denied states and the timing limits in UI. [Apple: background processes](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac), [notification authorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:))

FSEvents and incremental background scans remain deferred. They are not prerequisites for periodic volume-capacity checks or net differences between manual scans.

## Test and release strategy

- Synthetic trees: hard links, APFS clones, sparse/compressed files, packages, long/Unicode paths, nested symlinks, denied paths, changing identities, mounts and interrupted scans.
- Disposable cloud account/folders: placeholders, pinned files, pending uploads, conflicts, offline operation and eviction failure. Verify no scan-triggered content hydration.
- Adapter fixtures: supported/unknown versions, configured alternate paths, active apps, source/release artifacts and tool failures/timeouts. Unknown semantics fail closed.
- Privacy matrix: fresh/denied/revoked grants; signed versus development identity; selected scopes with/without FDA; container restrictions on supported releases.
- Execution: target substitution races, cancellation, crash between journal and mutation, Trash failure, partial batches and recovery guidance.
- Performance: fixed reference machine/data and measured resource budgets from the PRD; publish scope/conditions with any scan-speed claims.
- Alerts: initial low reading, threshold crossing, 5 GB recovery margin, repeated launches, disabled/revoked notifications, delayed timers, wake, unavailable metric, threshold edits, 24-hour snooze, login approval, window close versus Quit, and no filesystem scan invoked by a capacity check.
- Release: valid signature/notarization, no debug entitlements, clean-machine install/uninstall and no orphaned background registration.

Disk-space and file-metadata APIs may require privacy-manifest reasons. Audit each API actually used against Apple's current required-reason list before distribution; include only valid purposes and avoid using disk signals for tracking. [Apple: disk-capacity API notice](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey)

## Feasibility gates and open decisions

1. Confirm direct-distribution access behavior and FDA optional coverage on target systems.
2. Prove metadata-only cloud scans, reliable pin/sync detection and safe local eviction; fall back to Finder guidance if unsupported.
3. Validate allocation estimates and clearly communicate the limits of exclusive-space accounting.
4. Select exact initial adapters from measured storage opportunities; verify command scopes before execution.
5. Benchmark SQLite retention/query plan and memory use on a million-entry tree.
6. Confirm oldest macOS version and whether Intel testing justifies a universal launch build.
7. Validate growth comparisons and consequence-first plans; verify capacity-only alerts remain independent of scanning and cleanup.

Framework choice and on-demand operation are sufficiently clear to prototype now. Broad cleanup privileges, universal cloud support and exact reclaim estimates are not assumptions to hide inside implementation.

## Design synchronization — revision 0.8

[Design/spec contract](macos-cleaner-design-contract.md) maps UI behavior to this specification. Canonical preview: `storage-companion-direct.html`; OS permission/login controls and notification actions in it are simulations. Do not implement the historical cleanup space-target field. Change the PRD, technical specification, preview and contract together when revising alert policy or lifecycle.

### UI handoff boundary — revision 0.8

See [UI handoff review](macos-cleaner-ui-handoff-review.md) before extracting components. Distinguish unavailable/unknown sizes from zero, propagate partial coverage and stale eligibility into findings, and keep management-only inventory separate from executable actions. Preview simulations are not evidence of native integration or complete state coverage.

### UI state model — revision 0.8

Implement the typed states and recovery boundaries in the [UI state contract](macos-cleaner-ui-state-matrix.md). Distinguish scan lifecycle, permission/volume availability, cache-rule compatibility, cloud eligibility, plan freshness and capacity-reading validity. Carry affected resource identity and last valid observation time. Preserve independent eligibility for unaffected groups. Revalidate after any permission/volume recovery; never turn a UI retry directly into mutation. Capacity read failure pauses alert decisions without changing the saved threshold or alert intent.

## Layout and update boundaries — revision 0.8

Use a persistent native window shell and bounded content panes, with destination scroll restoration and stable row identities. Content measurement must not drive outer window geometry. Guard asynchronous results by request/scope identity. Implement and test the [window and interaction stability contract](macos-cleaner-layout-contract.md) across all state-matrix branches.

## Plan selection model — revision 0.8

Use one exact-target selection set for category controls, item/profile controls, totals and confirmation. Category activation materializes eligible identities from the current scan snapshot; partial selections derive a mixed checkbox state. Re-evaluation may remove ineligible targets but must not silently include newly eligible targets. A full scan establishes new eligibility and requires fresh selection. Completed/started execution invalidates reuse of the old general plan; targeted retries are separate approved subsets after revalidation. UI state is not authority to mutate: revalidate target identity, scope, exclusions, access, cloud state and browser activity independently. See [flow audit](macos-cleaner-flow-audit.md) for entry/return and management behavior.

## Review routes and selection — revision 0.8

Overview recommendations open the relevant item review. The item inspector offers Quick Look and Reveal in Finder; it has no “Exclude from cleanup” action. Item checkboxes determine this plan’s membership. Protected/offline items retain their read-only reason. Persistent scope exclusions belong in settings, not in the inspector.

Item review loads a scoped draft from the current plan. “Add selected items to cleanup plan” applies the reviewed scope and opens Cleanup plan; “Update cleanup plan” permits clearing an existing scoped selection. Preserve other categories and deduplicate target IDs. Leaving via Back does not apply an unsubmitted draft. Reopening review loads the committed plan. Browser-profile review follows the same contract. Inline category refinement edits the plan directly. Only “Review cleanup” opens the final confirmation; no review entry executes cleanup.

Keep a single context-labelled Back action, stable window bounds and destination scroll restoration. Selecting or inspecting an item must never navigate. Initial startup must not populate hidden selections.
