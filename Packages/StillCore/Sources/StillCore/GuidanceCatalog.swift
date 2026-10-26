import Foundation

extension BuiltInCatalog {
    private static func guidanceRule(_ id: String, _ title: String, detail: String, locations: [String], protected: Bool = false, _ guidance: Guidance) -> CleanupRule {
        CleanupRule(id: id, category: .managed, title: title, detail: detail,
                    consequence: "Guidance only. Still shows the size and where to manage it, and never changes it.",
                    regen: .userFile, action: .guidance, locations: locations, owner: nil, requiresFullDiskAccess: protected, guidance: guidance)
    }
    /// SPEC section 3, "Guidance only". Locations starting with `/` are read under the system root.
    static let guidanceRules: [CleanupRule] = [
        guidanceRule("device-backups", "iPhone and iPad backups",
                     detail: "Backups of your devices. Manage them in Finder: select a connected device, then Manage Backups.",
                     locations: ["Library/Application Support/MobileSync/Backup"], protected: true,
                     Guidance(place: .app(bundleID: "com.apple.finder"), placeName: "Finder")),
        guidanceRule("mail-attachments", "Mail attachments",
                     detail: "Attachments Mail downloaded. Remove large messages or attachments in Mail.",
                     locations: ["Library/Mail", "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], protected: true,
                     Guidance(sizing: .foldersNamed("Attachments"), place: .app(bundleID: "com.apple.mail"), placeName: "Mail")),
        guidanceRule("messages-attachments", "Messages attachments",
                     detail: "Photos, videos and files from your conversations. Review them in Messages, or in System Settings → General → Storage.",
                     locations: ["Library/Messages/Attachments"], protected: true,
                     Guidance(place: .app(bundleID: "com.apple.MobileSMS"), placeName: "Messages")),
        guidanceRule("photos-library", "Photos library",
                     detail: "Your Photos library. Photos manages it; with iCloud Photos, Optimize Mac Storage keeps smaller copies on this Mac.",
                     locations: ["Pictures/Photos Library.photoslibrary"], protected: true,
                     Guidance(place: .app(bundleID: "com.apple.Photos"), placeName: "Photos")),
        guidanceRule("time-machine-snapshots", "Time Machine local snapshots",
                     detail: "macOS keeps these and removes them on its own when space runs low. Their size isn’t reported.",
                     locations: [],
                     Guidance(sizing: .localSnapshots, place: .url(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!), placeName: "Storage Settings")),
        guidanceRule("xcode-archives", "Xcode archives",
                     detail: "Builds you archived to distribute. Keep the ones you may need to diagnose crashes; manage them in Xcode’s Organizer.",
                     locations: ["Library/Developer/Xcode/Archives"],
                     Guidance(place: .app(bundleID: "com.apple.dt.Xcode"), placeName: "Xcode")),
        guidanceRule("audio-plug-ins", "Audio plug-ins",
                     detail: "Plug-ins you bought or installed. Remove them with the vendor’s uninstaller, and reinstall through the vendor.",
                     locations: ["/Library/Audio/Plug-Ins", "Library/Audio/Plug-Ins"],
                     Guidance(place: .folder, placeName: "in Finder")),
        // Reason Studios installs Rack Extensions here: `Optional REs` holds Reason 13's additional devices (Reason Studios
        // Help, "Installing Additional Content in Reason 13"); `RackExtensions` is the field scan's folder (17 GB).
        guidanceRule("rack-extensions", "Rack Extensions",
                     detail: "Devices you bought or installed for Reason. Manage them in Reason Companion, which reinstalls them from your account.",
                     locations: ["RackExtensions", "Optional REs"].map { "Library/Application Support/Propellerhead Software/" + $0 },
                     Guidance(place: .folder, placeName: "in Finder")),
    ]
}
