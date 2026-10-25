import Foundation

public protocol ManagedApplicationLaunching: Sendable {
    func open(identifiers: [String]) async -> Bool
}
public enum ManagedGuidanceOpenResult: Sendable { case opened, unavailable }

public struct ManagedStorageGuidance: Sendable {
    public let category: ManagedStorageCategory
    public init(category: ManagedStorageCategory) { self.category = category }
    public var appName: String {
        switch category {
        case .releaseArchives: "Xcode"
        case .deviceBackups: "Finder"
        case .photos: "Photos"
        case .mail: "Mail"
        case .messages: "Messages"
        case .systemData: "System Settings"
        }
    }
    public var applicationIdentifiers: [String] {
        switch category {
        case .releaseArchives: ["com.apple.dt.Xcode"]
        case .deviceBackups: ["com.apple.finder"]
        case .photos: ["com.apple.Photos"]
        case .mail: ["com.apple.mail"]
        case .messages: ["com.apple.MobileSMS", "com.apple.iChat"]
        case .systemData: ["com.apple.systempreferences"]
        }
    }
    public var steps: String {
        switch category {
        case .releaseArchives: "In Xcode, choose Window → Organizer → Archives. Open Xcode launches the app; it does not open Organizer directly."
        case .deviceBackups: "In Finder, connect and select your device, then choose General → Manage Backups. Review backups in Finder's own interface."
        case .photos: "In Photos, choose Photos → Settings → iCloud → Optimize Mac Storage if you use iCloud Photos. Photos manages its own library."
        case .mail: "In Mail, use View → Sort By → Size to review large messages. Mailbox → Erase Deleted Items permanently removes discarded mail."
        case .messages: "In Messages, select a conversation and open the contact or group information to review attachments. View → Recently Deleted manages removed items."
        case .systemData: "In System Settings, choose General → Storage. System Data is managed by macOS. General → Time Machine explains backup settings and local snapshots."
        }
    }
    public var consequence: String {
        switch category {
        case .releaseArchives: "Keep archives and matching debug symbols for distributed builds; they may be needed to diagnose crashes. Still does not inspect or remove release archives."
        case .deviceBackups: "Deleting a backup in Finder cannot be recovered there. Archive a backup you want to preserve against replacement. Still does not edit or remove backups."
        case .photos: "With iCloud Photos enabled, deleting photos can delete them on all synced devices. Optimization is different from deleting originals."
        case .mail: "Message → Remove Attachments can delete IMAP attachments from the mail server. Do not treat message or attachment deletion as local cache clearing."
        case .messages: "With Messages in iCloud enabled, deletion also applies to your other enabled devices. It does not retract recipients' copies. Retention settings can remove messages automatically."
        case .systemData: "System Data is not an independently reclaimable category. Time Machine snapshots are automatically managed and their space is counted as available; do not count it again as guaranteed savings."
        }
    }
    public var supportURL: URL {
        let path: String
        switch category {
        case .releaseArchives: return URL(string: "https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information")!
        case .deviceBackups: path = "/en-ca/108809"
        case .photos: path = "/en-ca/guide/photos/phtf5e48489c/mac"
        case .mail: path = "/guide/mail/delete-emails-and-manage-storage-mlhlp1001/mac"
        case .messages: path = "/guide/messages/delete-messages-and-conversations-icht1035/mac"
        case .systemData: path = "/guide/mac-help/mchl3d437fbc/mac"
        }
        return URL(string: "https://support.apple.com")!.appendingPathComponent(path)
    }
    public func open(using launcher: any ManagedApplicationLaunching) async -> ManagedGuidanceOpenResult {
        await launcher.open(identifiers: applicationIdentifiers) ? .opened : .unavailable
    }
}
