import Foundation
import Darwin

/// Uninstalling a plug-in product as a whole (#176, Decisions 42, 50, 51): every format of it, plus the support files its own
/// installer receipt lists. Items a suite receipt lists for several products, and vendor content (Decision 52), are shared:
/// listed under each product that shares them, ticked one by one only and counted once. Only what macOS lets the user move to
/// the Trash without a password is offered, checked at the scan and again before acting. It goes through `AppUninstall`'s
/// path: its `Target`, review lines, History and Put back.
public enum PlugInUninstall {
    public static let formatsRuleID = "uninstall-plugin"
    public static let filesRuleID = "uninstall-plugin-files"
    public static let sharedRuleID = "uninstall-plugin-shared"
    public static let rules: [CleanupRule] = [
        CleanupRule(id: formatsRuleID, category: .apps, title: "Formats", detail: "The product's plug-in formats.", consequence: AppUninstall.consequence,
                    regen: .userFile, action: .trash, locations: [], owner: nil),
        CleanupRule(id: filesRuleID, category: .apps, title: "Its support files", detail: "Presets and support files its own installer lists.",
                    consequence: AppUninstall.consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth),
        CleanupRule(id: sharedRuleID, category: .apps, title: "Shared with other products",
                    detail: "Suite support files and content other products use too. Tick each one yourself.",
                    consequence: AppUninstall.consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth,
                    itemByItem: true),
    ]

    /// Plug-in hosts that must be closed first (Decision 51, a curated list). Bundle IDs checked on this Mac: Ableton Live
    /// (`com.ableton.live`) and Pro Tools (`com.avid.ProTools`); the rest are their makers' published IDs, and every host is
    /// also matched by its executable's name.
    public static let hosts: [RuleOwner] = [
        RuleOwner(name: "Logic Pro", bundleIDs: ["com.apple.logic10"], executables: ["Logic Pro*"]),
        RuleOwner(name: "GarageBand", bundleIDs: ["com.apple.garageband10"], executables: ["GarageBand"]),
        RuleOwner(name: "MainStage", bundleIDs: ["com.apple.mainstage3"], executables: ["MainStage*"]),
        RuleOwner(name: "Ableton Live", bundleIDs: ["com.ableton.live"], executables: ["Live"]),
        RuleOwner(name: "Reason", bundleIDs: ["com.reasonstudios.reason", "com.propellerheads.reason"], executables: ["Reason", "Reason [0-9]*"]),
        RuleOwner(name: "Pro Tools", bundleIDs: ["com.avid.ProTools"], executables: ["Pro Tools"]),
        RuleOwner(name: "Cubase", executables: ["Cubase*"]),
        RuleOwner(name: "Studio One", executables: ["Studio One*"]),
        RuleOwner(name: "Bitwig Studio", bundleIDs: ["com.bitwig.BitwigStudio"], executables: ["Bitwig*"]),
        RuleOwner(name: "FL Studio", bundleIDs: ["com.image-line.flstudio"], executables: ["FL Studio*"]),
        RuleOwner(name: "REAPER", bundleIDs: ["com.cockos.reaper"], executables: ["REAPER", "reaper"]),
    ]

    /// Where a receipt's support files may be: anything else it lists (the system, launch daemons, apps) is never offered.
    static let supportPlaces = ["Library/Application Support/", "Library/Audio/Presets/", "Library/Preferences/"]
    /// Apple's folders (Decision 41): its loops and the Logic library, never offered even when a receipt lists them.
    static let appleFolders: Set<String> = ["apple", "logic", "garageband", "mainstage", "apple loops", "logic pro library.bundle"]

    /// Every product's items, ready to tick. `listings` is each receipt's listed paths (`listings(of:under:)`); `content`
    /// the vendor content tied to products (`MusicContent`, by product ID). What `offered` already holds stays there.
    public static func scan(_ inventory: PlugInInventory, apps: [InstalledApp], listings: [String: Set<String>], content: [MusicContentItem] = [],
                            systemRoot: URL, offered: [Candidate] = [], exclusions: ExclusionPolicy = ExclusionPolicy(),
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let products = inventory.products.filter { !$0.isApple }
        let catalog = Catalog(rules: rules)
        var sharers: [String: [String]] = [:]
        for product in products { for receipt in product.receipts { sharers[receipt, default: []].append(product.id) } }
        var shared: [String: Candidate] = [:], items: [Candidate] = []
        func item(_ rule: CleanupRule, _ url: URL) -> Candidate? {
            var info = stat()
            guard lstat(url.path, &info) == 0, [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT), !isNeverTouched(url, below: systemRoot),
                  let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(url, volumeID: volume) else { return nil }
            let size = sizer.size(url)
            return catalog.candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
                .found(under: url.deletingLastPathComponent())
        }
        let taken = RemovedAppLeftovers.notOffered
        for product in products {
            let bundleID = product.files.lazy.compactMap(\.bundleID).first ?? ""
            let standalone = ownApp(of: product, among: apps)
            let tool = VendorTool.known.first { $0.makes(bundleID) }.flatMap { tool in apps.first { $0.bundleID.lowercased() == tool.bundleID } }
            var target = AppUninstall.Target(name: product.name, bundleID: standalone?.bundleID ?? bundleID, path: product.id,
                                             helpers: standalone.map { AppUninstall.helperIDs(of: URL(fileURLWithPath: $0.path)) } ?? [])
            target.otherPaths = product.files.map(\.url.path) + (standalone.map { [$0.path] } ?? [])
            target.hosts = hosts; target.tool = tool?.name
            var own: [Candidate] = []
            for file in product.files {
                // An AUv3 lives inside its app and goes with it.
                if file.format == .auv3 { target.insideApp += 1; continue }
                guard var format = item(rules[0], file.url) else { continue }
                guard Removability.canMoveToTrash(file.url) else { target.needsPassword += 1; continue }
                format.leftover = LeftoverTie(app: product.name, bundleID: file.bundleID, vendor: RemovedAppLeftovers.vendor(of: file.bundleID ?? ""), evidence: .bundleID)
                own.append(format)
            }
            for receipt in product.receipts {
                let ids = sharers[receipt] ?? []
                for url in supportRoots(listings[receipt] ?? [], systemRoot: systemRoot) {
                    if ids.count > 1 { if shared[url.path] == nil, let found = item(rules[2], url) { shared[url.path] = found.shared(by: ids, receipt: receipt) }; continue }
                    guard var file = item(rules[1], url) else { continue }
                    guard taken(offered, [file]).count == 1 else { target.inPlan += 1; continue }
                    guard Removability.canMoveToTrash(url) else { target.needsPassword += 1; continue }
                    file.leftover = LeftoverTie(app: product.name, bundleID: nil, vendor: RemovedAppLeftovers.vendor(of: receipt), evidence: .receipt(receipt))
                    own.append(file)
                }
            }
            items += own.map { var item = $0; item.uninstall = target; return item }
            // Shared items carry the first sharer's target, for its owner and checks.
            for key in shared.keys where shared[key]?.uninstall == nil { shared[key]?.uninstall = target }
        }
        for piece in content where piece.kind == .installed {
            let ids = piece.owners.filter { id in products.contains { $0.id == id } }
            guard let first = ids.first, shared[piece.url.path] == nil, let target = items.first(where: { $0.uninstall?.path == first })?.uninstall,
                  var found = item(rules[2], piece.url) else { continue }
            found = found.shared(by: piece.owners, receipt: nil); found.uninstall = target
            shared[piece.url.path] = found
        }
        let sharedItems = taken(offered + items, shared.values.sorted { $0.url.path < $1.url.path }).filter { Removability.canMoveToTrash($0.url) && $0.uninstall != nil }
        return items + sharedItems
    }

    /// The product's own standalone app: one of its vendor named like it, or the app an AUv3 of it is in.
    static func ownApp(of product: PlugInProduct, among apps: [InstalledApp]) -> InstalledApp? {
        let vendors = Set(product.files.compactMap(\.vendor)), name = RemovedAppLeftovers.token(product.name)
        let containers = product.files.filter { $0.format == .auv3 }.map { $0.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path }
        return apps.first { containers.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) }
            ?? apps.first { vendors.contains(RemovedAppLeftovers.vendor(of: $0.bundleID)) && RemovedAppLeftovers.token($0.name) == name }
    }

    /// The items a receipt installed whole: the shallowest listed paths in a support place whose every entry on disk the
    /// receipt lists, so a maker's folder that other products also fill is never taken, only this product's folder in it.
    static func supportRoots(_ listed: Set<String>, systemRoot: URL) -> [URL] {
        let base = systemRoot.standardizedFileURL.path.hasSuffix("/") ? systemRoot.standardizedFileURL.path : systemRoot.standardizedFileURL.path + "/"
        var roots: [String] = []
        for path in listed.sorted(by: { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) }) {
            guard path.hasPrefix(base), !roots.contains(where: { path.hasPrefix($0 + "/") }) else { continue }
            let relative = String(path.dropFirst(base.count))
            guard let place = supportPlaces.first(where: relative.hasPrefix), relative.count > place.count, isWhollyListed(path, listed) else { continue }
            roots.append(path)
        }
        return roots.map { URL(fileURLWithPath: $0) }
    }
    static func isWhollyListed(_ path: String, _ listed: Set<String>, limit: Int = 20_000) -> Bool {
        guard listed.contains(path) else { return false }
        guard let walk = FileManager.default.enumerator(atPath: path) else { return true }
        var seen = 0
        while let relative = walk.nextObject() as? String {
            seen += 1
            if seen > limit || !listed.contains(path + "/" + relative) { return false }
        }
        return true
    }

    /// Never offered or acted on: license and macOS data and Apple's folders anywhere on the path below the system root, and
    /// anything that is or holds an app or plug-in other than the item itself.
    static func isNeverTouched(_ url: URL, below systemRoot: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents.dropFirst(systemRoot.standardizedFileURL.pathComponents.count)
        return parts.contains { RemovedAppLeftovers.isNeverOffered($0) || appleFolders.contains($0.lowercased()) }
            || parts.dropLast().contains { $0.lowercased().hasSuffix(".app") }
    }

    /// The check just before acting (Decision 50): never license, macOS or Apple data by its name (its folders were checked at
    /// the scan, and the item can't leave them and keep its path); a format is still the bundle the scan tied to the product;
    /// and macOS still lets the user move it to the Trash without a password.
    static func refusal(for candidate: Candidate) -> CheckRefusal? {
        let url = candidate.url
        if isNeverTouched(url, below: url.deletingLastPathComponent()) { return .protected(url.lastPathComponent) }
        if candidate.ruleID == formatsRuleID {
            guard let tie = candidate.leftover, PlugInInventory.info(url)?["CFBundleIdentifier"] as? String == tie.bundleID else { return .changed }
        }
        return Removability.canMoveToTrash(url) ? nil : .notPermitted
    }

    /// Each receipt's listed paths (`lsbom`), absolute, for the receipts `ids` names. A receipt that can't be read lists nothing.
    public static func listings(of ids: Set<String>, under systemRoot: URL) -> [String: Set<String>] {
        let folder = systemRoot.appendingPathComponent("var/db/receipts"), lsbom = URL(fileURLWithPath: "/usr/bin/lsbom")
        var found: [String: Set<String>] = [:]
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where name.hasSuffix(".plist") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let id = info["PackageIdentifier"] as? String, ids.contains(id), let prefix = info["InstallPrefixPath"] as? String, prefix.hasPrefix("/") || prefix.isEmpty,
                  let listing = try? BoundedTool.run(executable: lsbom, arguments: ["-s", folder.appendingPathComponent(String(name.dropLast(6)) + ".bom").path],
                                                     timeout: 5, outputLimit: 8 << 20) else { continue }
            let base = systemRoot.appendingPathComponent(String(prefix.drop { $0 == "/" }))
            found[id] = Set(listing.split(separator: "\n").map { line in
                base.appendingPathComponent(line.hasPrefix("./") ? String(line.dropFirst(2)) : String(line)).standardizedFileURL.path
            })
        }
        return found
    }
}

extension Candidate {
    /// A shared item, under every product in `products` ("Shared with <N> products").
    func shared(by products: [String], receipt: String?) -> Candidate {
        var item = self
        item.sharedBy = products
        item.leftover = LeftoverTie(app: "", bundleID: nil, vendor: receipt.map(RemovedAppLeftovers.vendor(of:)) ?? "", evidence: receipt.map { .receipt($0) } ?? .bundleID)
        return item
    }
    /// Whether it is uninstalled with the app or product whose row is `id`: its own, or one it is shared with.
    public func isUninstalled(with id: String) -> Bool { uninstall?.path == id || sharedBy.contains(id) }
}
