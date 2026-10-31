import Foundation

/// The volume a path is on, as the app reads it from the file system (#559).
public struct MountedVolume: Equatable, Sendable {
    public var path: String
    public var isReadOnly: Bool
    public var isDiskImage: Bool
    public init(path: String, isReadOnly: Bool, isDiskImage: Bool) {
        self.path = path; self.isReadOnly = isReadOnly; self.isDiskImage = isDiskImage
    }
}

/// Where the running copy of CacheDrop is (#559, Decision 124). Opened from a disk image, macOS runs it from the image or
/// from a randomized read-only copy (App Translocation), where updates can't install; those two offer the move.
public enum AppBundleLocation: Equatable, Sendable {
    case applications, userApplications, buildProducts, other
    /// Straight from a mounted disk image.
    case diskImage(volume: String)
    /// From App Translocation; `original` is where macOS says the app really is, when it says, and `diskImageVolume`
    /// the disk image that original is on, if any.
    case translocated(original: String?, diskImageVolume: String?)

    /// `original` asks macOS for a translocated bundle's real path; `volume` gives the volume holding a path.
    public static func classify(bundle: String, home: String, original: (String) -> String?, volume: (String) -> MountedVolume?) -> AppBundleLocation {
        func onDiskImage(_ path: String) -> String? {
            guard path.hasPrefix("/Volumes/"), let mounted = volume(path), mounted.isReadOnly || mounted.isDiskImage else { return nil }
            return mounted.path
        }
        if isTranslocated(bundle) {
            let real = original(bundle)
            return .translocated(original: real, diskImageVolume: real.flatMap(onDiskImage))
        }
        if let image = onDiskImage(bundle) { return .diskImage(volume: image) }
        if bundle.hasPrefix("/Applications/") { return .applications }
        if bundle.hasPrefix((home as NSString).appendingPathComponent("Applications") + "/") { return .userApplications }
        let components = bundle.split(separator: "/")
        if components.contains("DerivedData") || zip(components, components.dropFirst()).contains(where: { $0 == "Build" && $1 == "Products" }) {
            return .buildProducts
        }
        return .other
    }

    /// macOS's translocation mounts live in the per-user temporary folders, under an `AppTranslocation` folder.
    static func isTranslocated(_ path: String) -> Bool {
        (path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/"))
            && path.split(separator: "/").contains("AppTranslocation")
    }

    public var offersMove: Bool {
        switch self {
        case .diskImage, .translocated: true
        case .applications, .userApplications, .buildProducts, .other: false
        }
    }
    /// The disk image to eject once the moved copy runs.
    public var diskImageToEject: String? {
        switch self {
        case .diskImage(let volume): volume
        case .translocated(_, let volume): volume
        case .applications, .userApplications, .buildProducts, .other: nil
        }
    }
}
