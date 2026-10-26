import Foundation

/// A setting that moves an app's data away from the folders a rule names, so the rule must not act on them.
/// Paths starting with "/" are system paths; others are relative to the home folder. A `*` matches any folder,
/// and `$USER` is the current user's short name.
public enum LayoutOverride: Sendable {
    /// A dotted key path set in a property list or JSON file.
    case key(file: String, keyPath: String)
    /// Text that appears in a file, such as a Firefox pref name in `prefs.js`.
    case text(file: String, contains: String)

    func isSet(home: URL, systemRoot: URL) -> Bool {
        let (file, test): (String, (Data) -> Bool)
        switch self {
        case .key(let path, let keyPath):
            file = path
            test = { data in
                let object = (try? PropertyListSerialization.propertyList(from: data, format: nil)) ?? (try? JSONSerialization.jsonObject(with: data))
                let value = keyPath.split(separator: ".").reduce(object as Any?) { ($0 as? [String: Any])?[String($1)] }
                return value != nil && !(value is NSNull) && (value as? String)?.isEmpty != true
            }
        case .text(let path, let needle):
            file = path
            test = { String(decoding: $0, as: UTF8.self).contains(needle) }
        }
        let resolved = file.replacingOccurrences(of: "$USER", with: NSUserName())
        let isSystem = resolved.hasPrefix("/")
        let urls = Catalog.pathsMatching(String(resolved.drop { $0 == "/" }), under: isSystem ? systemRoot : home.resolvingSymlinksInPath()).map(\.0)
        // Settings files are small; a huge one is not a settings file.
        return urls.contains { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 5_000_000,
                  let data = try? Data(contentsOf: url) else { return false }
            return test(data)
        }
    }
}

extension Catalog {
    /// Rules whose owner keeps its data somewhere else by a setting. They offer nothing, and the plan says why.
    public func overriddenRules(home: URL, systemRoot: URL = URL(fileURLWithPath: "/")) -> [CleanupRule] {
        rules.filter { $0.layoutOverrides.contains { $0.isSet(home: home, systemRoot: systemRoot) } }
    }
}
