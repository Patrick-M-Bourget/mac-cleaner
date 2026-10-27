import Foundation

/// The bundles other than apps that make a product installed (#251): every audio plug-in `PlugInInventory` finds (AU, VST, VST3,
/// AAX, CLAP, AUv3), with its maker, and the bundles in the standard places for preference panes, services, drivers, other
/// plug-ins and the helpers makers keep in `Application Support`. Read-only: only Info.plists are read, nothing is sized or loaded.
public enum InstalledBundles {
    /// Folders read under both the system root and the home; locations of bundles that aren't audio plug-ins.
    static let places = ["Library/PreferencePanes", "Library/Services", "Library/Application Support", "Library/Audio/Plug-Ins/HAL",
                         "Library/Audio/MIDI Drivers", "Library/Internet Plug-Ins", "Library/Spotlight", "Library/QuickLook"]
    static let extensions: Set<String> = ["app", "bundle", "plugin", "prefpane", "service", "driver", "component", "appex", "xpc", "qlgenerator", "mdimporter"]
    /// Levels looked into below each place, never inside a bundle: `Application Support/<maker>/<product>/<helper>.app`.
    static let depth = 3

    public static func scan(home: URL, systemRoot: URL = URL(fileURLWithPath: "/")) -> [InstalledApp] {
        let plugIns = PlugInInventory.files(home: home, systemRoot: systemRoot, sizer: nil).compactMap { file -> InstalledApp? in
            guard file.bundleID != nil || file.maker != nil else { return nil }
            return InstalledApp(name: file.name, bundleID: file.bundleID ?? "", path: file.url.path, maker: file.maker)
        }
        let others = places.flatMap { [systemRoot.appendingPathComponent($0), home.appendingPathComponent($0)] }.flatMap { bundles(in: $0, depth: depth) }
        return plugIns + others.compactMap { url in
            guard let info = PlugInInventory.info(url), let id = info["CFBundleIdentifier"] as? String else { return nil }
            return InstalledApp(name: url.deletingPathExtension().lastPathComponent, bundleID: id, path: url.path, maker: PlugInInventory.copyrightHolder(info))
        }
    }

    /// Bundles in `folder` and in folders without an extension below it, `depth` levels down; never follows a symlink.
    static func bundles(in folder: URL, depth: Int) -> [URL] {
        guard depth > 0, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.sorted().flatMap { name -> [URL] in
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard !name.hasPrefix("."), lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return [] }
            if extensions.contains(url.pathExtension.lowercased()) { return [url] }
            return url.pathExtension.isEmpty ? bundles(in: url, depth: depth - 1) : []
        }
    }
}
