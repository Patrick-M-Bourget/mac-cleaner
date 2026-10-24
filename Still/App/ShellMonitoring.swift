import SwiftUI

/// Presentation of the controller's typed evidence, never a parser of status prose.
struct MonitoringFooter: View {
    let state: AlertShellState
    let openDetails: () -> Void
    var body: some View {
        Group {
            if state == .off {
                Label(MonitoringPresentation.title(state), systemImage: MonitoringPresentation.symbol(state))
            } else {
                Button(action: openDetails) {
                    Label(MonitoringPresentation.title(state), systemImage: MonitoringPresentation.symbol(state))
                }.buttonStyle(.plain).accessibilityLabel(MonitoringPresentation.title(state))
                    .accessibilityHint("Open Storage alerts details without changing settings")
            }
        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 16)
    }
}

struct MonitoringDetails: View {
    let state: AlertShellState
    let effective: Bool
    var body: some View {
        SettingsRow(title: MonitoringPresentation.title(state), detail: MonitoringPresentation.detail(state)) {
            Text(effective ? "Capacity polling is active while Still runs." : "Capacity polling is stopped.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum MonitoringPresentation {
    static func title(_ state: AlertShellState) -> String {
        switch state {
        case .off: "On-demand scanning"
        case .checking: "Checking alerts…"
        case .on: "Storage alerts on"
        case .snoozed: "Alerts snoozed"
        case .attention: "Alerts need attention"
        }
    }
    static func symbol(_ state: AlertShellState) -> String {
        switch state {
        case .off: "lock"
        case .checking: "clock"
        case .on: "bell.badge"
        case .snoozed: "bell.slash"
        case .attention: "exclamationmark.triangle"
        }
    }
    static func detail(_ state: AlertShellState) -> String {
        switch state {
        case .off: "Storage alerts are off. Folder scans run only when you choose."
        case .checking: "Verifying notification access and startup-volume capacity. No folder scan is running."
        case .on: "Startup-volume capacity checks are verified while Still runs. Quit stops checks; Start at Login is separate."
        case .snoozed(let until): "Alerts are snoozed until \(until.formatted()). Capacity checks continue while Still runs; Quit stops them."
        case .attention(let reason):
            switch reason {
            case .savedStateUnavailable: "Saved alert state couldn’t be read. Monitoring is stopped to preserve suppression."
            case .saveFailed: "Alert state couldn’t be saved. Monitoring is stopped to prevent repeat notifications."
            case .notificationsUnavailable: "Notifications are unavailable. Review Still’s notification access in System Settings."
            case .capacityUnavailable: "A valid startup-volume capacity reading is unavailable. Alert decisions are paused."
            case .invalidThreshold: "The applied threshold no longer fits this volume. Update it before resuming alerts."
            case .submissionFailed: "The notification couldn’t be submitted. A later capacity check may retry."
            }
        }
    }
}
