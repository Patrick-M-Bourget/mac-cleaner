# Native development

Native UI implementation follows the mandatory [design system](DESIGN-SYSTEM.md).

The native workspace starts with deterministic in-memory fixtures (issue #2). Issue #3 adds explicit native folder selection and read-only metadata inspection. Nothing scans until the user chooses a folder. Quick Look and Reveal in Finder run only from their explicit controls; preview requires fresh positive locality and matching resource identity. No cleanup target mutation is implemented. Fixture strings and sizes remain illustrative; selecting a real folder replaces fixture findings in that session.

## Prerequisites and launch

- Full Xcode with Swift 6 language mode is required, rather than Command Line Tools alone. Local validation uses **Xcode 27.1**; hosted CI pins **Xcode 26.6**, explicitly available in the macOS 26 runner inventory. Hosted validation is a separate compatibility gate until that job passes.
- The deployment target is provisionally macOS 14. This development slice is validated on the local Apple silicon host; macOS 14 and Intel compatibility are not certified by that result.
- Open `Still/Still.xcodeproj`, choose the shared **Still** scheme and **My Mac**, then Run. Debug uses local ad-hoc signing and needs no team or distribution credentials.

From the repository root, when Xcode is installed at its standard path:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Still/Still.xcodeproj -scheme Still -destination 'platform=macOS' -derivedDataPath .build/xcode
open .build/xcode/Build/Products/Debug/Still.app
```

Using `DEVELOPER_DIR` per command avoids changing the machine's global developer-directory selection. The native CI job builds this same runnable target, rather than a separate test-only implementation. The [official runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists Xcode 26.6 on macOS 26 (checked October 22, 2026); Xcode 27.1 is not listed there. CI therefore pins 26.6 instead of assuming the local toolchain exists on hosted runners. The Swift 6 language mode and macOS 14 deployment target are shared; the first hosted result must establish cross-toolchain compatibility.

## Fixture journey and UI tests

Overview → Review Downloads → inspect a filename → View cleanup plan → Choose items. Names inspect without selecting; the plan stays empty. History and Locations & access are honest shell states. Appearance follows the system by default, with Light/Dark overrides in the toolbar. Command–1 through Command–4 navigate Overview, Cleanup plan, History and Locations & access. All controls remain native keyboard-focusable. The persistent shell uses a 1120 × 760 initial content target and 900 × 640 minimum; navigation/disclosures do not request a different window size.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Still/Still.xcodeproj -scheme Still -destination 'platform=macOS' -derivedDataPath .build/xcode
```

Run UI tests from an unlocked logged-in graphical session. XCTest may require the host's developer/UI automation authorization. Preserve normal ad-hoc signing: disabling signing builds successfully but the UI runner can be killed before connecting. Test data are embedded values; the suite requires no elevated access and must not target real user files.

The focused UI suite observes native accessibility controls, fixture inspection, navigation and unchanged outer-window geometry. This cannot certify native permission dialogs, cloud sync, filesystem safety, VoiceOver quality, localization or adapter compatibility. Those remain separate milestone gates.

## Structure

`Still/App` owns the current SwiftUI composition; `Still/UITests` owns user-journey tests. Keep future filesystem/persistence adapters behind domain interfaces, outside view bodies. No empty packages or speculative mutation implementations are included in the shell slice. Distribution signing, Hardened Runtime validation and notarization remain M7 work; the locally runnable build is not a release artifact.

## Folder inspection validation

Choose folder opens NSOpenPanel with directory-only single selection. Scan metadata runs serially in a non-MainActor scanner actor, checks cancellation between observations, and balances successful security-scoped access around the operation. No bookmark persists the scope yet. The scan never requests content, thumbnail generation, hashing or a cloud download.

The scanner reports logical file bytes separately from allocated bytes, and selected-volume total/available capacity separately from scanned inventory. Available capacity prefers Foundation's important-usage metric and explicitly labels an available-capacity fallback, matching the alert policy; unavailable readings remain Unknown. The selected volume need not be the startup volume. Repeated hardlink identities count once; APFS clones/snapshots are not exclusive-space estimates. Package rows and symlink rows remain visible, with no recursive package or symlink-target inventory. Cross-volume descendants are skipped. Root symlinks are rejected. Enumeration is not a transactional filesystem snapshot.

Bounds are 100,000 observations and depth 64. Reaching a bound or an access/read failure records incomplete coverage. A blocked metadata syscall may delay cancellation; no task is launched per file. The list uses lazy native rows.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Packages/StillCore
```

Disposable-tree tests exercise paths/times/logical bytes, package/symlink containment, hardlink accounting, unknown allocation/locality, bounded scans and rejection of unconfirmed previews. A native UI journey creates its own temporary text file, chooses its directory through NSOpenPanel and inspects its size/path without changing contents. Tests never choose personal folders or invoke preview/download on cloud files. Local cloud metadata support is not proof of File Provider/iCloud non-hydration; real disposable provider/OS tests remain a milestone gate. Native permission revocation, disconnected volumes and deeper partial-scan recovery are expanded in issue #4.
## Future storage-alert development slice (#27)

Storage Alerts is hidden in the M1 navigation. To inspect this M5 development capability, launch the built app with an explicit argument:

```sh
open .build/xcode/Build/Products/Debug/Still.app --args --future-milestones
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Still/Packages/StorageAlerts
```

There is no product milestone picker. The flag exposes Storage Alerts only; it does not qualify the milestone or enable notifications automatically. Alerts begin off, with a suggested 40 decimal GB threshold. Visiting settings reads startup-volume capacity to establish the valid range; enabling is a separate user action and is the only path to requesting OS notification permission. Automated tests never enable native notifications or request that permission.

The native adapter reads `volumeAvailableCapacityForImportantUsage` and total capacity on `/`, never enumerates files or invokes scanning/execution. A repeating 900-second Timer with tolerance runs only while alert intent and effective notification authorization permit it; wake/activation coalesce within 60 seconds, recheck authorization, and resume denied polling only after authorization becomes effective. Missing readings pause decisions. A low episode submits once; recovery is threshold + 5 GB capped at total capacity. Submission failure permits a later retry; a successful submission does not assert that Focus or Notification Center displayed it. Notification opening activates Overview without scanning.

The initial #27 slice was process-local; the #28/#29 sections below describe the integrated lifecycle and durable suppression. These capabilities remain development-only pending signed native qualification. Native notification delivery and denied/revoked OS behavior still require a disposable signed-app manual integration pass; pure policy tests inject authorization/capacity/time and do not certify OS UI.

The app bundles a privacy manifest declaring disk-space reason `85F4.1` (displaying disk-space information). Disk values remain local and are shown to the user; no tracking/export occurs. Re-audit all actual APIs and purposes during M7 distribution qualification. Primary API references: [Apple capacity API](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey), [notification authorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)), [notification settings](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)), and [required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Future menu-bar and login lifecycle (#28)

The existing `--future-milestones` flag also exposes independent Start Still at Login controls. Merely visiting settings or reading saved intent never registers a service. Only an explicit toggle calls `SMAppService.mainApp.register/unregister`; native status refresh on activation distinguishes enabled, approval-required, disabled and unavailable. A failed registration retains requested intent and shows the actual OS status plus on-demand guidance. No helper, LaunchAgent or privileged daemon is installed. Automated tests use a disposable in-memory login-service implementation and never alter real login preferences or notification authorization.

Effective authorized monitoring inserts a native MenuBarExtra with Open Still and Quit. Closing the last workspace terminates idle on-demand/blocked-alert use when no plan or operation needs retention; effective alerts keep the same process and app-owned controller alive. Removing the menu extra turns alerts off. Explicit Quit stops the timer without changing saved login intent. The executor must set the shared operation-in-progress boundary; Quit waits for that boundary before terminating. No executor is present in this slice, so that integration remains a downstream requirement. Session selections must likewise live in app-owned state in the planning ticket, not a window-local draft.

Pure lifecycle/login tests cover window-close policy, pending-plan retention, safe Quit boundary, explicit registration, approval/status changes, unregister and unavailable on-demand operation. Fifteen merged package tests passed. A native UI smoke verified read-only login controls and termination after closing an alerts-off window; real signed-install login registration, user approval changes, menu removal, notification opening with a closed window and active-operation termination require disposable OS UI qualification. These tests do not certify Service Management behavior on the minimum OS. Sources: [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [last-window termination](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)), [termination decision](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)), [main-app login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register()), and [actual registration states](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum).

### Durable suppression and reminders (#29)

Alert preferences and episodes now persist atomically in the app's separate `Still/StorageAlerts/episode-state.json` support record, independently of scan history. Clear History must leave it untouched. Read/write corruption stops monitoring rather than silently resetting suppression. The journal stores intent before a notification submission and acceptance afterward: an interrupted uncertain submission is suppressed after restart, because OS acceptance/display cannot be inferred. Failed submissions retry no sooner than the normal 15-minute cadence; acceptance never retries merely because a banner was not visible.

“Remind me later” in settings or the notification's action stores a 24-hour deadline and one explicit reminder intent. Sampling continues passively while the app runs so genuine recovery can cancel the episode; it never schedules an OS wake or out-of-process reminder. Missing capacity after expiry does not notify. Recovery uses the episode's protected recovery threshold, capped at current volume capacity: lowering preferences cannot manufacture recovery. Raising a threshold may extend recovery; disabling cancels reminder intent but preserves episode suppression. New metric/volume context first establishes a baseline; metric changes preserve suppression and prior volumes retain their own episodes.

The capacity adapter records important-use versus fallback available capacity and startup-volume UUID. Unknown identity/readings pause decisions. Tests use temporary store URLs, controlled dates and samples, never the application's persistent user record or actual notification authorization. Native signed-app delivery, privacy and lifecycle qualification remain required before M5 ships.

The native manifest declares file-metadata reason `3B52.1` for selected-folder metadata, alongside the existing capacity declaration. The [Apple reason definition](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) covers sizes and other metadata of user-granted files/directories. Full release API audit remains M7.

## Future Homebrew review (#22)

With `--future-milestones`, Overview offers a secondary **Review Homebrew opportunities** route. Explicitly choose an executable, then Inspect. No real build is qualified, so the native path currently returns guidance without executing it; a clearly marked disposable example demonstrates target/estimate presentation. There is no automatic tool/cache discovery and no cleanup action. See [qualification evidence](validation/homebrew-preview.md) for bounded command tests, the disposable helper demonstration, primary sources and missing real-Homebrew validation gates.


## Read-only iCloud breakdown (#5)

Each explicit selected-scope result includes iCloud local allocation, cloud-only logical/allocation totals, unknown membership/locality and provider sync evidence. No cloud action is enabled. See [recorded opportunity and validation boundaries](validation/cloud-inventory.md); a consented bounded personal assessment is recorded, with remaining unobserved coverage explicitly unknown. Core tests inject provider metadata only over disposable files; the native UI journey keeps using its own ordinary temporary folder. No personal paths or contents are committed.
## Partial inspection and selected-scope recovery (#4)

Folder scans now carry affected paths and access-denied, revoked, unavailable-location and bounded/read-error recovery reasons. A failed root returns unavailable coverage with unknown totals, distinct from a successful empty folder. Known observed subtotals remain separate from complete-scope totals; uninspected packages and partial coverage prevent complete-size claims. No result represents whole-disk coverage. Access callbacks are injected only in disposable tests; real TCC revocation, volume unmount and signed-app permission behavior remain native integration gates.

The session retains independently selected locations and their last completed observations. Rechecking a failed location cannot erase other locations' useful results. Inspection displays historical observation times explicitly, lists each affected location and nearest recovery, and provides Recheck folder and Choose folder again actions. Removing a simulated denial does not make a saved partial report fresh: another explicit scan must complete first. No action eligibility is granted by cached observations or security-scope bookmark possession. Full Disk Access is not requested.

Selected-volume availability records Important usage versus Available capacity fallback versus Unavailable, matching the alert adapter's metric distinction. It does not silently label a fallback reading as important-use capacity. The selected scope's volume can differ from the startup volume monitored by alerts; these are not interchangeable readings.

The native UI regression selects a newly created temporary folder, removes only that owned fixture, and explicitly rechecks to verify unknown coverage, retained observation time, recovery controls and fixed window bounds. It does not revoke any actual OS grants or unmount volumes. CI also runs existing alert/lifecycle policy tests and isolated iCloud/Xcode/Chrome/Safari fixture packages without enabling real notifications or mutating personal application data.

## Future app-managed storage guidance (#31)

The future-milestone Overview entry opens a read-only management view for backups, Photos, Mail, Messages and system-managed data. No personal inventory runs automatically. Explicit selected-object metadata can establish a file allocation; protected folders/packages/links remain uninspected. All rows are management-only and contribute no cleanup targets or reclaimable estimates. See [scope, native instructions and validation](validation/managed-storage.md). Automated tests use fake launchers and disposable managed sentinels; no real owner apps or personal libraries are opened.
## Future pip inventory (#24)

With `--future-milestones`, Overview offers **Review pip cache opportunities**. Interpreter/cache selection is explicit, with useful unsupported guidance and no tool invocation for unqualified installations. A recorded reference demonstrates the genuine disposable pip 21.2.4 inventory evidence without probing the user's cache. See [qualification and reproduction](validation/pip-inventory.md); actual tests provision only an owned temporary venv through bundled ensurepip without network/global installation. Ordinary inventory never provisions packages or enables cleanup.

## Shared session selection (#7)

The application lifecycle singleton owns one live PlanDraft and inspection model. Item checkboxes, search results and Cleanup plan share exact directory-entry/action membership; filenames inspect only and View cleanup plan navigates without applying a staged draft. Filtering or Back never clears choices. A pending plan keeps the process alive when its window closes; reopening uses that same store. Explicit Quit clears the unexecuted draft; no plan or raw scan is serialized for restoration.

Only the configured user Downloads directory, verified by its directory resource identity, supplies the initial ordinary-file action. An arbitrary folder named Downloads is insufficient. Selected scopes must lie inside that root, and protected/managed extensions, package descendants, database files, symlinks and nonlocal/unknown targets remain browse-only. Presentation uses scan evidence; selecting performs fresh root/type/identity/ancestor checks and records the exact path, scope, root identity and modification evidence. These checks are non-destructive preflight, not race-safe execution authorization; final confirmation and an immutable executable plan arrive in #8–#9.

A hardlink's two directory entries remain two exact possible mutation targets; selecting one never silently substitutes its alias. Count selected paths separately and storage bytes once per resource identity. Repeated appearances of the same path/resource count once; overlapping scans are deduplicated in plan presentation. Existing selections remain visible separately from search results.

DEBUG UI tests may nominate a disposable root with `--ui-test-downloads-root` and `STILL_TEST_DOWNLOADS_ROOT`. Binding occurs only after that exact root is explicitly selected through NSOpenPanel. Its canonical final name must start with `StillSelectionUI-`, and its canonical parent must be the app temporary directory, `/private/tmp`, or the exact known UI runner container’s `Data/tmp` directory. Symlink roots or mappings outside those canonical parents fail closed. Debug compilation explicitly defines `DEBUG`; release builds contain no override. This supplies the configured root identity for tests without scanning real Downloads; it is not a release product setting or automatic scan. The selected root still goes through the folder picker and ordinary metadata scanner. No mutation is enabled in this slice.

Window > Show Still provides an explicit native route back to a closed pending-plan workspace, alongside Dock reopening. The app-owned inspection/selection objects survive window reconstruction; navigation state may return to Overview, and Cleanup plan retains membership. The focused native UI test verifies checkbox synchronization, filename inspection, hidden search selections, window close/reopen without alerts, and normal Quit/relaunch clearing the unexecuted plan.

## Bulk Downloads and approval boundary (#8)

The native Downloads category uses an AppKit mixed-state checkbox with current eligible count and logical bytes. Bulk selection materializes exact existing file IDs serially off MainActor; it never targets directories or selects subsequent discoveries. Root-level failures keep targets blocked, while a verified ordinary sibling outside an affected failed subtree can remain selectable. Protected package boundaries remain browse-only and unmeasured; they do not imply that independent ordinary files are inaccessible.

Review cleanup captures an immutable target list and draft generation. The fixed-size confirmation has bounded scrolling, exact relative paths, scope/count/size, Trash-held-space consequences and persistent Cancel/Approve controls. Cancel preserves selection and restores focus to Review cleanup. Any selection/scan generation change invalidates an open review. One final approval produces a separate immutable `CleanupApproval` value; no mutation API is invoked in #8. Updating the live plan cannot change an already produced value, and stale reviews cannot approve the new plan.

The execution ticket must consume approval and revalidate target evidence. `SessionPlan.canReview` is the shared readiness gate to extend for refresh/pending choices; `invalidateReview()` changes the generation without clearing membership. A preflight path check does not certify race-safe Trash execution. This build accurately states that approval moves no files until the executor is connected.

## Future Docker storage (#33)

`--future-milestones` exposes a secondary **Review Docker storage** route from Overview. Explicit selected-file metadata distinguishes logical image-file length, optional host allocation and unknown VM capacity/ownership. CLI/runtime inspection remains unsupported and unexecuted pending genuine disposable qualification. The synthetic report marks persistent volumes and offers no mutation. See [evidence and gates](validation/docker-inventory.md). No default Docker path/socket/context is searched.

### #8 checkpoint validation status

The focused native journey verified category bulk selection, mixed refinement, bounded confirmation geometry and Cancel preserving choices. It exposed unreliable keyboard focus restoration. A one-shot AppKit first-responder bridge now compiles, but its verification attempt ended with the UI runner killed during launch before reaching the control. Final approval/focus assertions are not yet qualified. Feature work is checkpointed for the design-system-first migration; do not treat this branch as completed #8 or enable execution from it.

The preceding #8 checkpoint status is historical. Native design-system qualification subsequently verified Cancel focus and final approval; #9 below connects that approved batch to execution.

## Downloads execution (#9)

Final **Move to Trash** now consumes the exact approved batch, journals native operations and shows per-file results with applicable Reveal in Trash actions. No permanent fallback exists. See [executor qualification and concurrency limits](validation/downloads-executor.md). Tests mutate only owned disposable fixtures. Launch recovery and completed-history management remain subsequent tickets; journal evidence persists independently of the session plan.

## Bounded progressive metadata scans (#34)

The optional public progress/cancellation boundary, bounded native updates and per-entry memory handling are documented with owned-tree measurements in [scanner performance evidence](validation/scanner-performance.md). Million-entry/reference-host, compressed-file and real mount/provider qualification remain open. Progress is preliminary and never authorizes cleanup.

## Refreshing selected findings

See [refresh validation](validation/refresh.md) for the per-scope pending-choice contract and disposable test evidence. The focused native journey is `WorkspaceUITests/testRefreshPreservesChoicesAndSearchThenExplainsChangedTargets`. Its DEBUG-only slow metadata boundary activates solely after selecting its explicitly bound owned fixture.

## Isolated local state for native tests

Execution, recovery and aggregate history use `LocalStateLocation.root(create:)`. Release builds always use local Application Support/Still. Debug native tests may supply `STILL_TEST_STATE_ROOT` and `STILL_TEST_STATE_ID` (`dev:ino`) for a canonical, owned 0700 `StillTestState-UUID` directory directly under the test process's temporary directory. Create an owned regular `.still-owned-test-state` marker containing the UUID suffix; bind the root's actual identity after creation. Invalid or incomplete bindings fail closed and never fall back to normal app state. This is a test boundary, not a product preference. Remove only the test's own root after the app stops.

Startup interruption review and actual SIGKILL fixture evidence are documented in [recovery validation](validation/startup-recovery.md). No session plan is restored as approval authority.

## Compatible aggregate comparisons (M4)

The future-milestone launch flag exposes **What grew** (Command-6). It records only completed, measured explicit-folder observations in local bounded aggregate history. See [comparison policy and validation](validation/growth-comparisons.md). Tests use the shared identity-bound disposable app-state root; do not point them at personal baseline storage.
