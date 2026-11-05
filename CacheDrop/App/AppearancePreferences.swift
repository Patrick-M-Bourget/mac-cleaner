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

/// The Settings window (⌘,), in five groups (#778, Decision 183): General, Notifications, Updates, Privacy and License,
/// each with the Form's own header and at most one footer. Appearance follows the system unless overridden here; the
/// menu bar item is shown and low-space alerts are off unless changed here (#131); the dry run is off unless turned on
/// here; the license key is entered and removed here (#594).
struct CacheDropSettingsView: View {
    @State private var appearance = AppLifecycleController.shared.appearance
    @AppStorage(PreferenceKeys.showsMenuBarItem) private var showsMenuBarItem = true
    @State private var sharing = SetupProgressSharing.shared
    @AppStorage(PreferenceKeys.checksForUpdatesAutomatically) private var checksForUpdatesAutomatically = true
    var body: some View {
        Form {
            Section {
                AppearancePicker(choice: Binding(get: { appearance.choice }, set: { AppLifecycleController.shared.chooseAppearance($0) }))
                if appearance.notice != nil { AppearancePreferenceNotice(notice: appearance.notice, retry: { appearance.retrySaving() }) }
                Toggle("Show free space in the menu bar", isOn: $showsMenuBarItem).accessibilityIdentifier("menuBarItemToggle")
                LoginSettingsView()
                DryRunToggle(model: AppLifecycleController.shared.selection.catalog)
            } header: {
                // Its footer is #768's `DryRunToggle.footer`, which arrives with that branch's merge.
                Text("General")
            }
            // #131: low-space alerts live here, not in the sidebar; the weekly reminder beside them (#599).
            Section {
                LowSpaceAlertsSettings(controller: AppLifecycleController.shared.alerts)
                WeeklyReminderSettings(controller: AppLifecycleController.shared.weeklyReminder)
            } header: {
                Text("Notifications")
            } footer: {
                footer("CacheDrop never scans or cleans in the background")
            }
            Section {
                // #600: weekly; Sparkle asks before downloading or installing anything (Decision 145).
                Toggle("Check for updates automatically", isOn: $checksForUpdatesAutomatically)
                    .accessibilityIdentifier("automaticUpdateChecksToggle")
                    .onChange(of: checksForUpdatesAutomatically) { _, _ in AppLifecycleController.shared.manualUpdater.automaticChecksChanged() }
                Button("Check for Updates…") { AppLifecycleController.shared.manualUpdater.checkForUpdates() }
                    .buttonStyle(.link).accessibilityIdentifier("checkForUpdatesSettings")
            } header: {
                Text("Updates")
            } footer: {
                footer("CacheDrop checks once a week")
            }
            // The one setting that sends anything, so never under General (#778).
            Section {
                Toggle(SetupProgressSharing.title, isOn: sharing.binding).accessibilityIdentifier("shareSetupProgressSettings")
            } header: {
                Text("Privacy")
            } footer: {
                footer(SetupProgressSharing.explanation)
            }
            LicenseSettings(license: AppLifecycleController.shared.license, trial: AppLifecycleController.shared.trial)
        }.formStyle(.grouped).frame(width: CacheDropDesign.Size.sheetNarrow).fixedSize(horizontal: false, vertical: true)
            .cacheDropButtonRule().background { SettingsOpensUnfocused() }
    }
    private func footer(_ text: String) -> some View {
        Text(text).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
    }
}

/// Settings opens with no field focused (#689, Decision 156). The License key field is its only text field, so AppKit
/// would put the cursor there each time the window opens; it takes focus only when clicked or tabbed to. Each opening
/// clears it once, after AppKit's own pick; switching back to an open Settings window keeps whatever was focused.
private struct SettingsOpensUnfocused: NSViewRepresentable {
    func makeNSView(context: Context) -> WatchView { WatchView() }
    func updateNSView(_ nsView: WatchView, context: Context) {}
    @MainActor final class WatchView: NSView {
        private var opening = true
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clearIfOpening() }
            })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.opening = true }
            })
            if window.isKeyWindow { clearIfOpening() }
        }
        private func clearIfOpening() {
            guard opening else { return }
            opening = false
            DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
        }
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
