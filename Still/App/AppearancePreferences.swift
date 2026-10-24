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
        try Data(value.utf8).write(to: file(createRoot: true), options: .atomic)
    }
    func remove() throws { try LocalStateLocation.removeKnownFile(filename) }
}

struct AppearancePicker: View {
    @Binding var choice: AppearanceChoice
    var body: some View {
        Picker("Appearance", selection: $choice) {
            ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.labelsHidden().controlSize(.small).frame(width: 110).accessibilityLabel("Appearance").accessibilityIdentifier("Appearance")
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
                NativeAppearanceRetryButton(action: retry).fixedSize()
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


/// Native target/action keeps the recovery control's accessible activation region
/// on the control itself, rather than the adjacent scrolling container's edge.
private struct NativeAppearanceRetryButton: NSViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> ActivationButton {
        let button = ActivationButton(title: "Retry saving", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setAccessibilityLabel("Retry saving")
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ActivationButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ nsView: ActivationButton, context: Context) { context.coordinator.action = action }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
    @MainActor final class ActivationButton: NSButton {
        override func accessibilityActivationPoint() -> NSPoint {
            // SwiftUI's wrapper can expose an activation point at the trailing
            // boundary, outside the actual native hit region. Keep native AX
            // activation at the current control center, including after a move.
            guard let window else { return super.accessibilityActivationPoint() }
            return window.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil))
        }
    }

}
