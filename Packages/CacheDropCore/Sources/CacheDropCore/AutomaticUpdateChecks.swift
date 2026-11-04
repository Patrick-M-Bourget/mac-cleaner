import Foundation

/// Check for updates automatically (#600, Decision 145): on unless turned off in Settings, once a week, never
/// downloading or installing by itself. Sparkle runs the schedule; this holds the rule the updater follows.
public enum AutomaticUpdateChecks {
    /// A week, Sparkle's `updateCheckInterval`.
    public static let interval: TimeInterval = 7 * 86_400
    public enum Check: Sendable { case requested, scheduled }

    /// The saved choice, on when nothing was saved. Disposable test runs never check on their own.
    public static func isOn(saved: Any?, disposableTest: Bool) -> Bool {
        !disposableTest && (saved as? Bool ?? true)
    }

    /// Whether a check may start: a requested one always unless an installation is pending (Decision 103); a scheduled
    /// one only while automatic checks are on.
    public static func allows(_ check: Check, automaticChecksOn: Bool, installationPending: Bool) -> Bool {
        guard !installationPending else { return false }
        return check == .requested || automaticChecksOn
    }
}
