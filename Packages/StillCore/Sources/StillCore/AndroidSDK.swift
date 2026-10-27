import Foundation
import Darwin

/// Android Studio's default layout: virtual devices in `~/.android/avd`, the SDK in `~/Library/Android/sdk`.
enum AndroidSDK {
    static let avdFolder = ".android/avd"
    static let sdkFolder = "Library/Android/sdk"
    static let unreadableNotice = "Couldn’t read which system image every Android virtual device uses, so no system image is offered."
    static let maximumConfigBytes = 1_000_000

    /// The `<name>.ini` Android Studio keeps beside a `<name>.avd` folder.
    static func iniFile(of avd: URL) -> URL { avd.deletingPathExtension().appendingPathExtension("ini") }

    /// How a system image folder is compared: absolute, standardized, symlinks resolved, no trailing slash.
    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    /// Every system image folder a virtual device uses, from each device's `config.ini` (`image.sysdir.N`).
    /// Nil when any device's settings can't be read or name no image, so nothing is guessed.
    static func referencedImages(home: URL) -> Set<String>? {
        let folder = home.appendingPathComponent(avdFolder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var devices = Set(names.filter { $0.hasSuffix(".avd") }.map { key(folder.appendingPathComponent($0)) })
        // A device kept elsewhere is found through its `.ini`.
        for name in names where name.hasSuffix(".ini") {
            guard let text = read(folder.appendingPathComponent(name)) else { return nil }
            if let path = values(in: text)["path"], path.hasPrefix("/") { devices.insert(key(URL(fileURLWithPath: path))) }
        }
        let sdk = home.appendingPathComponent(sdkFolder)
        var used = Set<String>()
        for device in devices {
            var info = stat()
            guard lstat(device, &info) == 0 else { continue }
            guard info.st_mode & S_IFMT == S_IFDIR, let text = read(URL(fileURLWithPath: device).appendingPathComponent("config.ini")) else { return nil }
            let images = values(in: text).filter { $0.key.hasPrefix("image.sysdir.") }.map(\.value).filter { !$0.isEmpty }
            guard !images.isEmpty else { return nil }
            for image in images { used.insert(key(image.hasPrefix("/") ? URL(fileURLWithPath: image) : sdk.appendingPathComponent(image))) }
        }
        return used
    }

    private static func read(_ url: URL) -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maximumConfigBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    /// `key=value` lines; the first value of each key wins.
    static func values(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces), value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if result[name] == nil { result[name] = value }
        }
        return result
    }

    /// "Android 34 · google_apis · arm64-v8a" for `android-34/google_apis/arm64-v8a`.
    static func imageName(_ parts: [String]) -> String {
        let api = parts.first.map { $0.hasPrefix("android-") ? "Android " + $0.dropFirst("android-".count) : $0 } ?? ""
        return ([api] + parts.dropFirst()).joined(separator: " · ")
    }
}

extension Catalog {
    /// Each `<name>.avd` folder in `folder`, named as Android Studio shows it, sized, with when it was last used.
    func androidVirtualDevices(in folder: URL, rule: CleanupRule, sizer: KnownLocationSizer) -> [Candidate] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".avd") && !$0.hasPrefix(".") }.sorted()
        return names.prefix(Self.childLimit).compactMap { name in
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
                  Protection(rule).protectedComponent(of: url, below: folder) == nil, CandidateCheck.protectedEntry(in: url, rule: rule) == nil else { return nil }
            let size = sizer.size(url)
            var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: Self.lastUsedInside(url, info))
            let config = try? String(contentsOf: url.appendingPathComponent("config.ini"), encoding: .utf8)
            let shown = config.flatMap { AndroidSDK.values(in: $0)["avd.ini.displayname"] }.flatMap { $0.isEmpty || $0.count > 100 ? nil : $0 }
            found.itemName = shown ?? (name as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
            return found
        }
    }

    /// Each system image folder (`<api>/<tag>/<abi>`) no virtual device uses. With a device whose image can't be read,
    /// nothing is offered and a note says why.
    func androidSystemImages(in root: URL, home: URL, rule: CleanupRule, sizer: KnownLocationSizer) -> ([Candidate], CatalogNote?) {
        func folders(_ url: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted().filter { name in
                var info = stat()
                return !name.hasPrefix(".") && lstat(url.appendingPathComponent(name).path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
            }
        }
        let paths = folders(root).flatMap { api in folders(root.appendingPathComponent(api)).flatMap { tag in
            folders(root.appendingPathComponent(api + "/" + tag)).map { [api, tag, $0] } } }
        guard !paths.isEmpty else { return ([], nil) }
        guard let used = AndroidSDK.referencedImages(home: home) else { return ([], CatalogNote(ruleID: rule.id, text: AndroidSDK.unreadableNotice)) }
        let found = paths.prefix(Self.childLimit).compactMap { parts -> Candidate? in
            let url = root.appendingPathComponent(parts.joined(separator: "/"))
            var info = stat()
            guard !used.contains(AndroidSDK.key(url)), lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
                  Protection(rule).protectedComponent(of: url, below: root) == nil, CandidateCheck.protectedEntry(in: url, rule: rule) == nil else { return nil }
            let size = sizer.size(url)
            var image = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: Self.lastUsedInside(url, info))
            image.itemName = AndroidSDK.imageName(parts)
            return image
        }
        return (found, nil)
    }
}
