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
            try Data(value.utf8).write(to: file(createRoot: true), options: .atomic)
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
                Button("Retry saving", action: retry).buttonStyle(.bordered).controlSize(.small).fixedSize()
            }
        }.frame(height: 24).accessibilityHidden(notice == nil)
        #if DEBUG
            .background(AppearanceRetryHitProbe())
        #endif
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


// Temporary owned diagnostic: every event is returned unchanged. No product authority.
func appearanceRetryProbe(_ event: String) {
    #if DEBUG
    guard LocalStateLocation.isDisposableTest,
          ProcessInfo.processInfo.arguments.contains("--ui-test-appearance-probe"),
          let root = try? LocalStateLocation.root(create: false) else { return }
    let target = root.appendingPathComponent("appearance-retry-probe.txt")
    var information = stat()
    if lstat(target.path, &information) == 0 {
        guard information.st_mode & S_IFMT == S_IFREG, information.st_uid == geteuid(), information.st_size < 16_384,
              target.path == target.resolvingSymlinksInPath().path else { return }
    } else if errno != ENOENT { return }
    var data = (try? Data(contentsOf: target)) ?? Data()
    data.append(Data(("[DEBUG-shell53-hit] " + event + "\n").utf8))
    try? data.write(to: target, options: .atomic)
    #endif
}

#if DEBUG
private struct AppearanceRetryHitProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ nsView: ProbeView, context: Context) {}
    @MainActor final class ProbeView: NSView {
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil, window != nil, LocalStateLocation.isDisposableTest,
                  ProcessInfo.processInfo.arguments.contains("--ui-test-appearance-probe") else { return }
            appearanceRetryProbe("hit-monitor.installed")
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.insetBy(dx: -2, dy: -2).contains(point) else { return event }
                let hit = window.contentView.flatMap { content in content.hitTest(content.convert(event.locationInWindow, from: nil)) }
                var names: [String] = []
                var view = hit
                while let current = view, names.count < 6 {
                    names.append(NSStringFromClass(type(of: current)))
                    view = current.superview
                }
                appearanceRetryProbe("event=" + String(event.type.rawValue) + " key=" + String(window.isKeyWindow) + " active=" + String(NSApp.isActive) + " modal=" + String(NSApp.modalWindow != nil) + " noticePoint=" + NSStringFromPoint(point) + " noticeBounds=" + NSStringFromRect(self.bounds) + " hit=" + names.joined(separator: ">"))
                return event
            }
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
#endif
