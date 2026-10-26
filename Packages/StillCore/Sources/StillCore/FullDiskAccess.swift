import Foundation
import Darwin

/// Whether Still has Full Disk Access (SPEC section 7). It's optional; Still works without it.
public enum FullDiskAccessStatus: Sendable, Equatable {
    case granted, notGranted
    /// No protected folder to check was found, so Still can't tell.
    case unknown
}

/// Detects Full Disk Access. The app uses `FullDiskAccessProbe`; tests and previews pass a fake.
public protocol FullDiskAccessDetecting: Sendable {
    func status() -> FullDiskAccessStatus
}

/// Checks whether a folder macOS protects behind Full Disk Access can be opened.
/// It only opens the folder itself and closes it again: it never lists or reads anything inside,
/// and never asks for access. The probed folders are ones macOS guards with Full Disk Access alone,
/// so a refusal never shows a privacy prompt (other apps' containers would, so they're not probed).
public struct FullDiskAccessProbe: FullDiskAccessDetecting {
    /// Folders inside the home folder, tried in order; the first that exists decides.
    public static let protectedFolders = ["Library/Safari", "Library/Application Support/com.apple.TCC"]
    public let home: URL
    public let folders: [String]
    public init(home: URL, folders: [String] = FullDiskAccessProbe.protectedFolders) { self.home = home; self.folders = folders }

    public func status() -> FullDiskAccessStatus {
        for folder in folders {
            let path = home.appendingPathComponent(folder).path
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 { close(fd); return .granted }
            switch errno {
            case EPERM, EACCES: return .notGranted
            default: continue // Missing or not a folder: try the next one.
            }
        }
        return .unknown
    }
}

/// Whether a rule's locations can be read with the current access. A row or catalog rule declares the
/// requirement with `CleanupRule.requiresFullDiskAccess`; views show `needsFullDiskAccess` as "Not accessible".
public enum RuleAccess: Sendable, Equatable { case available, needsFullDiskAccess }

extension CleanupRule {
    /// Only a known refusal blocks the rule. When access is unknown, sizing still reports what it couldn't read.
    public func access(given status: FullDiskAccessStatus) -> RuleAccess {
        requiresFullDiskAccess && status == .notGranted ? .needsFullDiskAccess : .available
    }
}

/// The one explanation every "not accessible" row and Locations & access show (SPEC section 7).
public enum FullDiskAccessGuide {
    public static let title = "Full Disk Access is optional"
    public static let summary = "Still works without it. Places macOS protects, such as Safari and Mail data, are listed as not accessible."
    public static let points = [
        "With it, Still can also see protected places like Safari and Mail data.",
        "It is broad read/write authority over your files, not a read-only permission.",
        "Still’s scans stay read-only. Nothing protected becomes eligible for cleanup, and Still only changes what you choose and review.",
        "You turn it on or off yourself in System Settings. Still never asks for it at launch.",
    ]
    /// The Full Disk Access list in Privacy & Security. The System Settings pane still answers to its legacy id on macOS 14 and later.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    public static func statusText(_ status: FullDiskAccessStatus) -> String {
        switch status {
        case .granted: "Granted"
        case .notGranted: "Not granted"
        case .unknown: "Couldn’t check"
        }
    }
}
