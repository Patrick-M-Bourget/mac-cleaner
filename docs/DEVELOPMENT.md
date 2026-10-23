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
