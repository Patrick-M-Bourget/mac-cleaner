import Foundation

/// Every non-Apple installer receipt's listed paths, read once (#291): what each receipt lists, and which receipts list each
/// path. A plug-in support item is a product's own only while no other receipt, plug-in or not, lists it or anything in it.
public struct ReceiptListings: Sendable {
    /// Each receipt's listed paths, absolute.
    public let byReceipt: [String: Set<String>]
    let byPath: [String: Set<String>]
    public init(_ byReceipt: [String: Set<String>]) {
        self.byReceipt = byReceipt
        var byPath: [String: Set<String>] = [:]
        for (id, paths) in byReceipt { for path in paths { byPath[path, default: []].insert(id) } }
        self.byPath = byPath
    }

    /// The receipts that list `path` or anything on disk inside it; nil when there is too much inside to look at.
    func listers(of path: String, limit: Int = 20_000) -> Set<String>? {
        var found = byPath[path] ?? []
        guard let walk = FileManager.default.enumerator(atPath: path) else { return found }
        var seen = 0
        while let relative = walk.nextObject() as? String {
            seen += 1
            if seen > limit { return nil }
            found.formUnion(byPath[path + "/" + relative] ?? [])
        }
        return found
    }

    /// Every non-Apple receipt in `<systemRoot>/var/db/receipts`, listed with `lsbom`. A receipt that can't be read lists nothing.
    public static func read(under systemRoot: URL) -> ReceiptListings {
        let folder = systemRoot.appendingPathComponent("var/db/receipts"), lsbom = URL(fileURLWithPath: "/usr/bin/lsbom")
        var found: [String: Set<String>] = [:]
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where name.hasSuffix(".plist") && !name.hasPrefix("com.apple.") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = info["PackageIdentifier"] as? String, let prefix = info["InstallPrefixPath"] as? String, prefix.hasPrefix("/") || prefix.isEmpty,
                  let listing = try? BoundedTool.run(executable: lsbom, arguments: ["-s", folder.appendingPathComponent(String(name.dropLast(6)) + ".bom").path],
                                                     timeout: 5, outputLimit: 8 << 20) else { continue }
            let base = systemRoot.appendingPathComponent(String(prefix.drop { $0 == "/" }))
            found[id] = Set(listing.split(separator: "\n").map { line in
                base.appendingPathComponent(line.hasPrefix("./") ? String(line.dropFirst(2)) : String(line)).standardizedFileURL.path
            })
        }
        return ReceiptListings(found)
    }
}
