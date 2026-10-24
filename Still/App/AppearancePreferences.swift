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
    func makeNSView(context: Context) -> ProbeButton {
        let button = ProbeButton(title: "Retry saving", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setAccessibilityLabel("Retry saving")
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProbeButton, context: Context) -> CGSize? { nsView.intrinsicContentSize }
    func updateNSView(_ nsView: ProbeButton, context: Context) { context.coordinator.action = action }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { appearanceRetryProbe("retry.action.enter"); action(); appearanceRetryProbe("retry.action.return") }
    }
    @MainActor final class ProbeButton: NSButton {
        #if DEBUG
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil, window != nil, LocalStateLocation.isDisposableTest,
                  ProcessInfo.processInfo.arguments.contains("--ui-test-appearance-probe") else { return }
            appearanceRetryProbe("native-monitor.installed")
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.insetBy(dx: -4, dy: -4).contains(point) else { return event }
                let hit = window.contentView.flatMap { content in
                    // AppKit hitTest receives a point in the receiver's SUPERview.
                    let parentPoint = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
                    return content.hitTest(parentPoint)
                }
                var views: [String] = []
                var current: NSView? = self
                while let view = current, views.count < 6 {
                    views.append(NSStringFromClass(type(of: view)) + " frame=" + NSStringFromRect(view.frame) + " bounds=" + NSStringFromRect(view.bounds) + " visible=" + NSStringFromRect(view.visibleRect))
                    current = view.superview
                }
                appearanceRetryProbe("event=" + String(event.type.rawValue) + " key=" + String(window.isKeyWindow) + " active=" + String(NSApp.isActive) + " modal=" + String(NSApp.modalWindow != nil) + " local=" + NSStringFromPoint(point) + " windowPoint=" + NSStringFromPoint(event.locationInWindow) + " hit=" + (hit.map { NSStringFromClass(type(of: $0)) } ?? "nil") + " selfHidden=" + String(self.isHiddenOrHasHiddenAncestor) + " selfEnabled=" + String(self.isEnabled) + " AXframe=" + NSStringFromRect(self.accessibilityFrame()) + " views=" + views.joined(separator: ">"))
                return event
            }
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            super.viewWillMove(toWindow: newWindow)
        }
        override func mouseDown(with event: NSEvent) {
            appearanceRetryProbe("native.mouseDown.enter")
            super.mouseDown(with: event)
            appearanceRetryProbe("native.mouseDown.return")
        }
        #endif
    }

}

// Temporary bounded trace in explicitly owned state, removed after diagnosis.
func appearanceRetryProbe(_ event: String) {
    #if DEBUG
    guard LocalStateLocation.isDisposableTest,
          ProcessInfo.processInfo.arguments.contains("--ui-test-appearance-probe"),
          let root = try? LocalStateLocation.root(create: false) else { return }
    let target = root.appendingPathComponent("appearance-retry-probe.txt")
    var info = stat()
    if lstat(target.path, &info) == 0 {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_size < 24_576,
              target.path == target.resolvingSymlinksInPath().path else { return }
    } else if errno != ENOENT { return }
    var data = (try? Data(contentsOf: target)) ?? Data()
    data.append(Data(("[DEBUG-shell53-center] " + event + "\n").utf8))
    try? data.write(to: target, options: .atomic)
    #endif
}
