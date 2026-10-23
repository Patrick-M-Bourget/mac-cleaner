# Native development

The native workspace currently implements issue #2 (M0 shell) using deterministic in-memory fixtures. It never scans a directory, reads personal file contents, requests folder permission, invokes Quick Look/Finder, or mutates cleanup targets. Fixture strings and sizes are illustrative. Selection, scan scopes and execution arrive in dependent tickets.

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

## Future storage-alert development slice (#27)

Storage Alerts is hidden in the M1 navigation. To inspect this M5 development capability, launch the built app with an explicit argument:

```sh
open .build/xcode/Build/Products/Debug/Still.app --args --future-milestones
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Still/Packages/StorageAlerts
```

There is no product milestone picker. The flag exposes Storage Alerts only; it does not qualify the milestone or enable notifications automatically. Alerts begin off, with a suggested 40 decimal GB threshold. Visiting settings reads startup-volume capacity to establish the valid range; enabling is a separate user action and is the only path to requesting OS notification permission. Automated tests never enable native notifications or request that permission.

The native adapter reads `volumeAvailableCapacityForImportantUsage` and total capacity on `/`, never enumerates files or invokes scanning/execution. A repeating 900-second Timer with tolerance runs only while alert intent and effective notification authorization permit it; wake/activation coalesce within 60 seconds, recheck authorization, and resume denied polling only after authorization becomes effective. Missing readings pause decisions. A low episode submits once; recovery is threshold + 5 GB capped at total capacity. Submission failure permits a later retry; a successful submission does not assert that Focus or Notification Center displayed it. Notification opening activates Overview without scanning.

This slice is process-local. Restart/snooze persistence and robust preference-change episode handling belong to #29. Menu-bar/window-close/Start at Login behavior belongs to #28. No login registration or launch agent is created here. Those missing lifecycle/persistence gates keep M5 development-only. Native notification delivery and denied/revoked OS behavior still require a disposable signed-app manual integration pass; pure policy tests inject authorization/capacity/time and do not certify OS UI.

The app bundles a privacy manifest declaring disk-space reason `85F4.1` (displaying disk-space information). Disk values remain local and are shown to the user; no tracking/export occurs. Re-audit all actual APIs and purposes during M7 distribution qualification. Primary API references: [Apple capacity API](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey), [notification authorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)), [notification settings](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)), and [required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Future menu-bar and login lifecycle (#28)

The existing `--future-milestones` flag also exposes independent Start Still at Login controls. Merely visiting settings or reading saved intent never registers a service. Only an explicit toggle calls `SMAppService.mainApp.register/unregister`; native status refresh on activation distinguishes enabled, approval-required, disabled and unavailable. A failed registration retains requested intent and shows the actual OS status plus on-demand guidance. No helper, LaunchAgent or privileged daemon is installed. Automated tests use a disposable in-memory login-service implementation and never alter real login preferences or notification authorization.

Effective authorized monitoring inserts a native MenuBarExtra with Open Still and Quit. Closing the last workspace terminates on-demand/blocked-alert use; effective alerts keep the same process and app-owned controller alive. Removing the menu extra turns alerts off. Explicit Quit stops the timer without changing saved login intent. The executor must set the shared operation-in-progress boundary; Quit waits for that boundary before terminating. No executor is present in this slice, so that integration remains a downstream requirement. Session selections must likewise live in app-owned state in the planning ticket, not a window-local draft.

Pure lifecycle/login tests cover window-close policy, safe Quit boundary, explicit registration, approval/status changes, unregister and unavailable on-demand operation. Native build passed; real signed-install login registration, user approval changes, menu removal, notification opening with a closed window and active-operation termination require disposable OS UI qualification. These tests do not certify Service Management behavior on the minimum OS. Sources: [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [last-window termination](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)), [termination decision](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)), [main-app login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register()), and [actual registration states](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum).
