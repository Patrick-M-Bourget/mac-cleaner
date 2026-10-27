import Foundation

/// The one explanation every "not accessible" row and Locations & access show (SPEC section 7).
public enum FullDiskAccessGuide {
    public static let title = "Full Disk Access is optional"
    public static let summary = "CacheDrop works without it. Places macOS protects, such as Safari and Mail data, are listed as not accessible."
    public static let points = [
        "With it, CacheDrop can also see protected places like Safari and Mail data.",
        "It is broad read/write authority over your files, not a read-only permission.",
        "CacheDrop’s scans stay read-only. Nothing protected becomes eligible for cleanup, and CacheDrop only changes what you choose and review.",
        "You turn it on or off yourself in System Settings. CacheDrop never asks for it at launch.",
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
