import AppKit
import Darwin
import Foundation
import CacheDropCore
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
        try Data(value.utf8).write(to: file(createRoot: true), options: .atomic)
    }
    func remove() throws { try LocalStateLocation.removeKnownFile(filename) }
}

extension AppearanceChoice {
    /// What the picker shows. The stored raw value stays "Automatic".
    var title: String { self == .automatic ? "System" : rawValue }
}

struct AppearancePicker: View {
    @Binding var choice: AppearanceChoice
    var body: some View {
        Picker("Appearance", selection: $choice) {
            ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("Appearance")
    }
}

/// The Settings window (⌘,). Appearance follows the system unless overridden here; the menu bar item is shown and
/// low-space alerts are off unless changed here (#131); the dry run is off unless turned on here; the license key is
/// entered and removed here (#594).
struct CacheDropSettingsView: View {
    @State private var appearance = AppLifecycleController.shared.appearance
    @AppStorage(PreferenceKeys.showsMenuBarItem) private var showsMenuBarItem = true
    var body: some View {
        Form {
            Section {
                AppearancePicker(choice: Binding(get: { appearance.choice }, set: { AppLifecycleController.shared.chooseAppearance($0) }))
                if appearance.notice != nil { AppearancePreferenceNotice(notice: appearance.notice, retry: { appearance.retrySaving() }) }
                Toggle("Show free space in the menu bar", isOn: $showsMenuBarItem).accessibilityIdentifier("menuBarItemToggle")
                LoginSettingsView()
            }
            // #131: low-space alerts live here, not in the sidebar.
            LowSpaceAlertsSettings(controller: AppLifecycleController.shared.alerts)
            Section { DryRunToggle(model: AppLifecycleController.shared.selection.catalog) }
            Section {
                Button("Check for Updates…") { AppLifecycleController.shared.manualUpdater.checkForUpdates() }
                    .buttonStyle(.link).accessibilityIdentifier("checkForUpdatesSettings")
            }
            LicenseSettings(license: AppLifecycleController.shared.license, trial: AppLifecycleController.shared.trial)
        }.formStyle(.grouped).frame(width: CacheDropDesign.Size.sheetNarrow).fixedSize(horizontal: false, vertical: true)
            .cacheDropButtonRule()
    }
}

/// A bounded persistent row below the toolbar, above the right-hand content only.
struct AppearancePreferenceNotice: View {
    let notice: AppearancePreferenceController.Notice?
    let retry: () -> Void
    var body: some View {
        HStack(spacing: CacheDropDesign.Space.sm) {
            Spacer(minLength: 0)
            Text(message).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("appearanceSaveNotice")
                .accessibilityHidden(notice == nil)
            if notice == .saveFailed {
                NativeAppearanceRetryButton(action: retry).fixedSize()
            }
        }.frame(height: 24)
    }
    private var message: String {
        switch notice {
        case .invalidSavedValue: "Saved appearance isn’t recognized. Using System."
        case .unreadable: "Couldn’t read saved appearance. Using System."
        case .saveFailed: "Appearance wasn’t saved."
        case nil: " "
        }
    }
}


/// Native target/action keeps the recovery control's accessible activation region
/// on the control itself, rather than the adjacent scrolling container's edge.
private struct NativeAppearanceRetryButton: NSViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> AccessibleButton {
        let button = AccessibleButton(title: "Retry saving", target: context.coordinator, action: #selector(Coordinator.clicked))
        // A status line's action is a link, never a small bordered button (#311).
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setAccessibilityLabel("Retry saving")
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AccessibleButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ nsView: AccessibleButton, context: Context) { context.coordinator.action = action }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
    @MainActor final class AccessibleButton: NSButton {
        override func accessibilityFrame() -> NSRect {
            // NSButton's expanded alignment/shadow AX frame can put a default
            // click on the wrapper's excluded trailing boundary. Report the
            // actual current native bounds in screen coordinates instead.
            guard let window else { return super.accessibilityFrame() }
            return window.convertToScreen(convert(bounds, to: nil))
        }
    }

}
