import AppKit
import Darwin
import Foundation
import StillCore
import SwiftUI

/// One known app-owned preference file. Opening the app never repairs invalid data.
@MainActor final class NativeAppearancePreferenceStore: AppearancePreferenceStore {
    private let filename = "appearance-preference.txt"
    private func file(createRoot: Bool) throws -> URL {
        let url = try LocalStateLocation.root(create: createRoot).appendingPathComponent(filename)
        var information = stat()
        if lstat(url.path, &information) == 0 {
            guard information.st_mode & S_IFMT == S_IFREG, information.st_uid == geteuid(),
                  information.st_size <= 128, url.path == url.resolvingSymlinksInPath().path else { throw CocoaError(.fileReadNoPermission) }
        } else if errno != ENOENT { throw CocoaError(.fileReadUnknown) }
        return url
    }
    func read() throws -> String? {
        let url = try file(createRoot: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
    func write(_ value: String) throws {
        appearanceRetryProbe("write.enter")
        do {
            let target = try file(createRoot: true)
            appearanceRetryProbe("write.target.directoryHint=" + String(target.hasDirectoryPath))
            try Data(value.utf8).write(to: target, options: .atomic)
            appearanceRetryProbe("write.complete")
        } catch {
            let failure = error as NSError
            appearanceRetryProbe("write.error domain=" + failure.domain + " code=" + String(failure.code))
            throw error
        }
    }
    func remove() throws { try LocalStateLocation.removeKnownFile(filename) }
}

struct AppearancePicker: View {
    @Binding var choice: AppearanceChoice
    var body: some View {
        Picker("Appearance", selection: $choice) {
            ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.controlSize(.small).frame(width: 110).accessibilityLabel("Appearance")
    }
}

/// A bounded persistent row below the toolbar, above the right-hand content only.
struct AppearancePreferenceNotice: View {
    let notice: AppearancePreferenceController.Notice?
    let retry: () -> Void
    var body: some View {
        HStack(spacing: StillDesign.Space.sm) {
            Spacer(minLength: 0)
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("appearanceSaveNotice")
            if notice == .saveFailed {
                Button("Retry saving", action: retry).controlSize(.small).fixedSize()
            }
        }.frame(height: 24).accessibilityHidden(notice == nil)
    }
    private var message: String {
        switch notice {
        case .invalidSavedValue: "Saved appearance isn’t recognized. Using Automatic."
        case .unreadable: "Couldn’t read saved appearance. Using Automatic."
        case .saveFailed: "Appearance wasn’t saved."
        case nil: " "
        }
    }
}

/// Temporary, explicitly owned native-action diagnosis. Removed after the probe.
func appearanceRetryProbe(_ event: String) {
    #if DEBUG
    guard LocalStateLocation.isDisposableTest,
          ProcessInfo.processInfo.arguments.contains("--ui-test-appearance-probe"),
          let root = try? LocalStateLocation.root(create: false) else { return }
    let line = "[DEBUG-shell53-appearance] " + event + "\n"
    NSLog("%@", line)
    let target = root.appendingPathComponent("appearance-retry-probe.txt")
    var information = stat()
    if lstat(target.path, &information) == 0 {
        guard information.st_mode & S_IFMT == S_IFREG, information.st_uid == geteuid(), information.st_size < 16_384,
              target.path == target.resolvingSymlinksInPath().path else { return }
    } else if errno != ENOENT { return }
    var data = (try? Data(contentsOf: target)) ?? Data()
    data.append(Data(line.utf8))
    try? data.write(to: target, options: .atomic)
    #endif
}
