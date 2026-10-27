import Foundation

/// Every non-Apple installer receipt's listed paths, read once (#291): what each receipt lists, and which receipts list each
/// path. A plug-in support item is a product's own only while no other receipt, plug-in or not, lists it or anything in it.
public struct ReceiptListings: Sendable {
    /// Each receipt's listed paths, absolute.
    public let byReceipt: [String: Set<String>]
    let byPath: [String: Set<String>]
    /// Installer records that couldn't be read (#291): while there is any, no support item is offered or moved, since an
    /// unread record is never "lists nothing".
    public let unread: [String]
    public init(_ byReceipt: [String: Set<String>], unread: [String] = []) {
        self.byReceipt = byReceipt; self.unread = unread
        var byPath: [String: Set<String>] = [:]
        for (id, paths) in byReceipt { for path in paths { byPath[path, default: []].insert(id) } }
        self.byPath = byPath
    }

    /// The receipts that list `path` or anything on disk inside it; nil when there is too much inside to look at.
    func listers(of path: String, limit: Int = 20_000) -> Set<String>? {
        var found = byPath[path] ?? []
        // An unreadable folder anywhere in it may hold what another receipt lists (#291).
        let ending = FileTree.entries(below: path, limit: limit) { entry, _ in found.formUnion(byPath[entry] ?? []); return false }
        return ending == .finished ? found : nil
    }

    /// Every non-Apple receipt in `<systemRoot>/var/db/receipts`, listed with `lsbom`. One that can't be read, or lists more than
    /// 64 MB or takes over 20 seconds, is `unread`.
    public static func read(under systemRoot: URL) -> ReceiptListings {
        let folder = systemRoot.appendingPathComponent("var/db/receipts"), lsbom = URL(fileURLWithPath: "/usr/bin/lsbom")
        var found: [String: Set<String>] = [:], unread: [String] = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where name.hasSuffix(".plist") && !name.hasPrefix("com.apple.") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = info["PackageIdentifier"] as? String, let prefix = info["InstallPrefixPath"] as? String, prefix.hasPrefix("/") || prefix.isEmpty,
                  let listing = try? BoundedTool.run(executable: lsbom, arguments: ["-s", folder.appendingPathComponent(String(name.dropLast(6)) + ".bom").path],
                                                     timeout: 20, outputLimit: 64 << 20),
                  // lsbom exits 0 when it can't read a BOM, with only its complaint; a real one lists `.` and paths under it (#291).
                  case let lines = listing.split(separator: "\n"), !lines.isEmpty, lines.allSatisfy({ $0.hasPrefix(".") }) else { unread.append(name); continue }
            let base = systemRoot.appendingPathComponent(String(prefix.drop { $0 == "/" }))
            found[id] = Set(lines.map { line in
                base.appendingPathComponent(line.hasPrefix("./") ? String(line.dropFirst(2)) : String(line)).standardizedFileURL.path
            })
        }
        return ReceiptListings(found, unread: unread)
    }
}
