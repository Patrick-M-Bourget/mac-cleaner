import Foundation

public enum AppLifecyclePolicy {
    public static func shouldKeepRunning(effectiveAlerts: Bool, operationInProgress: Bool, hasPendingPlan: Bool = false, menuBarItemShown: Bool = false) -> Bool {
        effectiveAlerts || operationInProgress || hasPendingPlan || menuBarItemShown
    }
    public static func mayQuit(operationInProgress: Bool) -> Bool { !operationInProgress }

    /// What a quit request does now (#130). A running cleanup asks first; once a stop is confirmed,
    /// or while maintenance runs, quitting waits for the current item and then completes on its own.
    public enum QuitDecision: Equatable, Sendable { case quitNow, askToStopCleanup, waitForCurrentItem }
    public static func quitDecision(cleanupRunning: Bool, maintenanceInProgress: Bool, stopConfirmed: Bool) -> QuitDecision {
        if maintenanceInProgress { return .waitForCurrentItem }
        guard cleanupRunning else { return .quitNow }
        return stopConfirmed ? .waitForCurrentItem : .askToStopCleanup
    }
}

/// The question asked when quitting during a cleanup (#130). Cancel is the default and keeps it running;
/// only an explicit "Stop and Quit" stops the cleanup after the current item.
@MainActor public struct QuitDuringCleanupPrompt {
    public enum Answer: Sendable { case keepRunning, stopAndQuit }
    public static let message = "A cleanup is running. Stop after this item and quit?"
    /// In order; the first is the default button.
    public static let buttons = ["Cancel", "Stop and Quit"]
    private let ask: @MainActor () -> Answer
    public init(ask: @escaping @MainActor () -> Answer) { self.ask = ask }
    /// Asks, and stops the cleanup only when confirmed. Returns whether to quit once the current item finishes.
    public func confirm(stopCleanup: () -> Void) -> Bool {
        guard ask() == .stopAndQuit else { return false }
        stopCleanup()
        return true
    }
}

/// A normal launch always opens the main window (#110). macOS's saved window state could restore
/// the app with no main window, so CacheDrop ignores it, as `-ApplePersistenceIgnoreState YES` does.
/// Registered defaults rank lowest, so an explicit setting can still override this.
public enum AppLaunchPolicy {
    public static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: ["ApplePersistenceIgnoreState": true])
    }
}

public enum LoginStatus: String, Sendable { case enabled, requiresApproval, disabled, unavailable }
@MainActor public protocol LoginService: AnyObject {
    var status: LoginStatus { get }
    func register() throws
    func unregister() throws
}
/// Reading OS status never registers, even if an old preference requests login launch.
@MainActor public final class LoginRegistration {
    public private(set) var intent: Bool
    public private(set) var status: LoginStatus
    private let service: any LoginService
    public init(service: any LoginService, savedIntent: Bool = false) {
        self.service = service; self.intent = savedIntent; self.status = service.status
    }
    public func refresh() { status = service.status }
    public func choose(_ enabled: Bool) throws {
        intent = enabled
        defer { refresh() }
        if enabled { try service.register() } else { try service.unregister() }
    }
}

/// The menu bar item (#131): free space in a short form, and the menu's item titles.
public enum MenuBarStatus {
    /// "38 GB free": whole gigabytes from 10 GB, one decimal below that, terabytes from 1,000 GB. Decimal units,
    /// as Finder shows them. Nil when capacity is unknown, so the item shows only its symbol.
    public static func freeSpaceTitle(available: Int64?, locale: Locale = .current) -> String? {
        guard let available, available >= 0 else { return nil }
        let gigabytes = Double(available) / 1_000_000_000
        let (value, unit, digits) = gigabytes >= 1_000 ? (gigabytes / 1_000, "TB", 1) : gigabytes >= 10 ? (gigabytes, "GB", 0) : (gigabytes, "GB", 1)
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " " + unit + " free"
    }

    public enum Item: Equatable, Sendable {
        case openCacheDrop, scanAgain, smartClean, settings, quit
        public var title: String {
            switch self {
            case .openCacheDrop: "Open CacheDrop"
            case .scanAgain: "Scan again"
            case .smartClean: "Smart clean…"
            case .settings: "Settings…"
            case .quit: "Quit CacheDrop"
            }
        }
    }
}
