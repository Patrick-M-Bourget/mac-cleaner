import CoreGraphics
import Foundation

// Only the ephemeral Actions GUI session may change its virtual display mode.
guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["RUNNER_OS"] == "macOS" else {
    print("Display setup is restricted to the ephemeral macOS runner.")
    exit(1)
}
let display = CGMainDisplayID()
let previous = CGDisplayBounds(display)
let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
let suitable = modes.filter { $0.width >= 1440 && $0.height >= 900 }
    .sorted { $0.width * $0.height < $1.width * $1.height }
var outcome = "already-large-enough"
if previous.width < 1440 || previous.height < 900 {
    if let mode = suitable.first {
        outcome = CGDisplaySetDisplayMode(display, mode, nil) == .success ? "changed-owned-virtual-display" : "mode-change-unavailable"
    } else { outcome = "no-larger-mode-available" }
}
let actual = CGDisplayBounds(display)
let record: [String: Any] = ["outcome": outcome, "previousWidth": previous.width, "previousHeight": previous.height,
    "actualWidth": actual.width, "actualHeight": actual.height,
    "availableModes": modes.map { ["width": $0.width, "height": $0.height] }]
let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
