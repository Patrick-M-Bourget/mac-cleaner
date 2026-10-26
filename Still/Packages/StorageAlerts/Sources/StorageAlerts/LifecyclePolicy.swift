import Foundation

public enum AppLifecyclePolicy {
    public static func shouldKeepRunning(effectiveAlerts: Bool, operationInProgress: Bool, hasPendingPlan: Bool = false) -> Bool {
        effectiveAlerts || operationInProgress || hasPendingPlan
    }
    public static func mayQuit(operationInProgress: Bool) -> Bool { !operationInProgress }
}

/// A normal launch always opens the main window (#110). macOS's saved window state could restore
/// the app with no main window, so Still ignores it, as `-ApplePersistenceIgnoreState YES` does.
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
