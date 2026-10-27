import Foundation

extension BuiltInCatalog {
    private static func guidanceRule(_ id: String, _ title: String, detail: String, locations: [String], protected: Bool = false, _ guidance: Guidance) -> CleanupRule {
        CleanupRule(id: id, category: .managed, title: title, detail: detail,
                    consequence: "Guidance only. CacheDrop shows the size and where to manage it, and never changes it.",
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
        // Every Photos library, renamed, additional or external (#180). Moving one whole: Apple Support 108345.
        guidanceRule("photos-library", "Photos libraries",
                     detail: "Your Photos libraries. Photos manages them: with iCloud Photos, turn on Optimize Mac Storage in Photos Settings → iCloud, or move a whole library to another drive (support.apple.com/108345). Deleting photos in an iCloud library deletes them on every device.",
                     locations: [], protected: true,
                     Guidance(sizing: .libraries(extension: "photoslibrary"), place: .app(bundleID: "com.apple.Photos"), placeName: "Photos",
                              learnMore: URL(string: "https://support.apple.com/en-au/108345"))),
        // Every Final Cut Pro library, renamed or external (#178). Generated media is removed in Final Cut itself:
        // File > Delete Generated Library Files (Apple Support 119610). Bundle identifier `com.apple.FinalCut`.
        guidanceRule("final-cut-libraries", "Final Cut Pro libraries",
                     detail: "Your Final Cut Pro libraries, with the media Final Cut generated. To remove generated media, select a library in Final Cut Pro, then choose File → Delete Generated Library Files. Render files are made again as you work; optimized and proxy media must be created again, and that needs the original media online.",
                     locations: [], protected: true,
                     Guidance(sizing: .libraries(extension: "fcpbundle"), place: .app(bundleID: "com.apple.FinalCut"), placeName: "Final Cut Pro",
                              learnMore: URL(string: "https://support.apple.com/en-au/119610"))),
        // Lightroom Classic's previews beside each catalog (#179), renamed or external; the catalog itself is never
        // listed. Lightroom builds normal previews again as needed (Adobe, "Preview cache error"); Smart Previews let
        // photos be edited while their originals are offline (Adobe, "Smart Previews"). Bundle id from Lightroom
        // Classic's Info.plist.
        guidanceRule("lightroom-previews", "Lightroom Classic previews",
                     detail: "Previews Lightroom Classic made of your photos, beside each catalog. To remove them, choose Library → Previews → Discard 1:1 Previews in Lightroom Classic, or set Catalog Settings → File Handling → Automatically Discard 1:1 Previews. Previews are built again when you view photos, which is slower at first. Your catalog and photos are not touched.",
                     locations: [], protected: true,
                     Guidance(sizing: .lightroomPreviews(smart: false), place: .app(bundleID: "com.adobe.LightroomClassicCC7"), placeName: "Lightroom Classic",
                              learnMore: URL(string: "https://helpx.adobe.com/lightroom-classic/desktop/kb/lightroom-gives-error-preview-cache.html"))),
        guidanceRule("lightroom-smart-previews", "Lightroom Classic Smart Previews",
                     detail: "Smart Previews let you edit photos while their originals are offline, such as on a disconnected drive. To remove them, select photos in Lightroom Classic and choose Library → Previews → Discard Smart Previews. Without them, photos whose originals are offline can’t be edited until the drive is connected again.",
                     locations: [], protected: true,
                     Guidance(sizing: .lightroomPreviews(smart: true), place: .app(bundleID: "com.adobe.LightroomClassicCC7"), placeName: "Lightroom Classic",
                              learnMore: URL(string: "https://helpx.adobe.com/lightroom-classic/help/lightroom-smart-previews.html"))),
        guidanceRule("time-machine-snapshots", "Time Machine local snapshots",
                     detail: "macOS keeps these and removes them on its own when space runs low. Their size isn’t reported.",
                     locations: [],
                     Guidance(sizing: .localSnapshots, place: .url(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!), placeName: "Storage Settings")),
        guidanceRule("xcode-archives", "Xcode archives",
                     detail: "Builds you archived to distribute. Keep the ones you may need to diagnose crashes; manage them in Xcode’s Organizer.",
                     locations: ["Library/Developer/Xcode/Archives"],
                     Guidance(place: .app(bundleID: "com.apple.dt.Xcode"), placeName: "Xcode")),
        // AU, VST, VST3 and CLAP in /Library and ~/Library, AAX in Avid's folder; listed by product (#174, Decision 42).
        guidanceRule("audio-plug-ins", "Audio plug-ins",
                     detail: "Plug-ins you bought or installed. Remove them with the vendor’s uninstaller, and reinstall through the vendor.",
                     locations: PlugInInventory.folders.map(\.location),
                     Guidance(sizing: .plugIns, place: .folder, placeName: "in Finder")),
        // Reason Studios installs Rack Extensions here: `Optional REs` holds Reason 13's additional devices (Reason Studios
        // Help, "Installing Additional Content in Reason 13"); `RackExtensions` is the field scan's folder (17 GB).
        guidanceRule("rack-extensions", "Rack Extensions",
                     detail: "Devices you bought or installed for Reason. Manage them in Reason Companion, which reinstalls them from your account.",
                     locations: ["RackExtensions", "Optional REs"].map { "Library/Application Support/Propellerhead Software/" + $0 },
                     Guidance(place: .folder, placeName: "in Finder")),
        // Audio production content (#139): libraries the user downloads again from the vendor, so never offered.
        // Logic Pro's Sound Library: Apple Loops in /Library/Audio/Apple Loops/Apple, impulse responses in
        // /Library/Audio/Impulse Responses/Apple, and sampler instruments and samples in /Library/Application Support/Logic
        // (Logic Pro User Guide, "Manage Logic Pro content"); loops the user made in ~/Library/Audio/Apple Loops (Apple
        // Support 101933, "Where are Apple Loops installed for Logic Pro for Mac and MainStage?"). GarageBand and MainStage
        // share this library. Its manager is in Logic: Logic Pro > Sound Library > Open Sound Library Manager. Logic's
        // bundle identifier is `com.apple.logic10`.
        guidanceRule("logic-sound-library", "Logic Pro and GarageBand sound library",
                     detail: "Instruments, samples and Apple Loops for Logic Pro, GarageBand and MainStage. Remove sound packs in Logic Pro: Sound Library, then Open Sound Library Manager.",
                     locations: ["/Library/Application Support/Logic", "/Library/Audio/Apple Loops/Apple", "/Library/Audio/Impulse Responses/Apple",
                                 "Library/Audio/Apple Loops"],
                     Guidance(place: .app(bundleID: "com.apple.logic10"), placeName: "Logic Pro")),
        // Ableton Live installs Packs in ~/Music/Ableton/Factory Packs by default (Ableton Help, "Resetting Live's
        // Library" and "The Live Browser"); a folder chosen in Settings > Library isn't found. Packs are managed in Live's
        // browser. Bundle identifier from Live 12's Info.plist.
        guidanceRule("ableton-packs", "Ableton Packs",
                     detail: "Packs installed for Ableton Live. Uninstall them in Live’s browser, under Packs, and download them again from your Ableton account.",
                     locations: ["Music/Ableton/Factory Packs"],
                     Guidance(place: .app(bundleID: "com.ableton.live"), placeName: "Ableton Live")),
        // Splice downloads sounds to ~/Splice by default (Splice Support, "Where is my Splice folder?"); a folder moved in
        // Splice's Preferences isn't found. Bundle identifier `com.splice.Splice` (the Splice app's Info.plist).
        guidanceRule("splice-samples", "Splice samples",
                     detail: "Sounds you downloaded from Splice. Manage them in the Splice app; they stay in your Splice library to download again.",
                     locations: ["Splice"],
                     Guidance(place: .app(bundleID: "com.splice.Splice"), placeName: "Splice")),
    ]
}
