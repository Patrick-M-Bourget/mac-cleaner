import Foundation

/// The one explanation every "not accessible" row and System access show (SPEC section 7).
public enum FullDiskAccessGuide {
    public static let title = "Broader access is optional"
    public static let summary = "Full Disk Access lets CacheDrop see protected places like Mail and Safari data. macOS grants more than reading; CacheDrop’s scans only read."
    /// The one note on how to turn it on. CacheDrop never asks for it at launch.
    public static let howToTurnOn = "Turn on CacheDrop in System Settings › Privacy & Security › Full Disk Access."

    /// One row of the sheet's coverage table.
    public struct CoverageRow: Equatable, Sendable {
        public let title: String
        public let value: String
        /// False while protected app data is left out (or not yet checked).
        public let included: Bool
    }
    /// What a scan covers now: your folders and known locations always, protected app data only with Full Disk Access.
    /// `nil` is "not checked yet".
    public static func coverage(_ status: FullDiskAccessStatus?) -> [CoverageRow] {
        let protected = switch status {
        case .granted: "Included"
        case .notGranted: "Not included"
        case .unknown: "Couldn’t check"
        case nil: "Checking…"
        }
        return [CoverageRow(title: "Scanned now", value: "Your folders and app caches", included: true),
                CoverageRow(title: "Protected app data", value: protected, included: status == .granted)]
    }
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
