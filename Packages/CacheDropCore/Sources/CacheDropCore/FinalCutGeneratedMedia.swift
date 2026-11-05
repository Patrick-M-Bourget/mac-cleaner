import Foundation
import Darwin

/// Final Cut Pro's generated media in each library (#399, Decision 171): render files, optimized media and proxy media.
/// Apple documents them as generated library files Final Cut makes and can delete (Apple Support 119610, "Delete generated
/// library files"; the Final Cut Pro Media Management white paper: render files are regenerated, optimized and proxy media
/// must be created again), but not the folder names inside a `.fcpbundle`. Those come from secondary sources, not observation:
/// - `<Event>/Render Files`, holding `High Quality Media`, `Peaks Data` and `Thumbnail Media`: dabase.com/blog/2020/FCPX_fcpbundle
///   (a library's listing), Apple Community thread 253873143, Creative COW "Cannot reduce 900GB fcpbundle file" (2024).
/// - `<Event>/Transcoded Media/High Quality Media` (optimized) and `<Event>/Transcoded Media/Proxy Media`: Grezzo's
///   fcpxml script (gist.github.com/Grezzo/6a730d449fb4a38147233b3469c29fe6), eoshd.com/?p=14905, Larry Jordan's
///   "FCP X: Working With Proxy Media" (2011, `Transcoded Media > Proxy Media`).
/// These folders sit beside original media, so only those exact names are matched, at that exact depth: an event is a visible
/// real folder directly inside the library, and every folder on the way is a real folder, never a link. Anything else in a
/// library, including a hidden `.fcpcache` folder one source shows, is never offered, so a wrong name finds nothing. Media
/// or cache storage set outside the library isn't looked for: where Final Cut records it is in its databases, never read.
/// A real check on a Mac with Final Cut Pro stays open (#741).
public enum FinalCutGeneratedMedia {
    static let renderFilesID = "final-cut-render-files", optimizedMediaID = "final-cut-optimized-media", proxyMediaID = "final-cut-proxy-media"
    static let ruleIDs: Set<String> = [renderFilesID, optimizedMediaID, proxyMediaID]
    static let libraryExtension = "fcpbundle"
    /// Each rule's folder inside an event folder, by exact name.
    static let layout: [String: [String]] = [
        renderFilesID: ["Render Files"],
        optimizedMediaID: ["Transcoded Media", "High Quality Media"],
        proxyMediaID: ["Transcoded Media", "Proxy Media"],
    ]
    /// Final Cut Pro and its trial, which has a bundle identifier of its own (pro-apps-dev list, 2011).
    static let owner = RuleOwner(name: "Final Cut Pro", bundleIDs: ["com.apple.FinalCut", "com.apple.FinalCutTrial"],
                                 executables: ["Final Cut Pro", "Final Cut Pro Trial"])
    /// The ticket's approved line for optimized and proxy media (#399).
    static let onlyCopy = "If the original media is offline or was deleted, this can be the only copy."

    /// The three rules. Libraries are searched for only with Full Disk Access, since the search reads Desktop, Documents and
    /// removable drives; without it they show as needing access only when Final Cut Pro is installed, as its libraries' row
    /// does (#245), and otherwise offer nothing.
    static func rules(apps: any AppLookup) -> [CleanupRule] {
        let installed = owner.bundleIDs.contains { apps.app(bundleID: $0) != nil }
        return [
            CleanupRule(id: renderFilesID, category: .photoVideo, title: "Final Cut Pro render files",
                        detail: "Files Final Cut Pro renders inside each library, not any it stores outside one.",
                        consequence: "Your libraries, projects and media are kept, and Final Cut Pro renders these files again as you work.",
                        regen: .cache, action: .delete, locations: [], owner: owner, requiresFullDiskAccess: installed),
            // Offered, never pre-ticked: the safety line is the default tick, not whether an item is offered (Decision 171).
            CleanupRule(id: optimizedMediaID, category: .photoVideo, title: "Final Cut Pro optimized media",
                        detail: "Apple ProRes copies of your media inside each library, not any stored outside one.",
                        consequence: onlyCopy, regen: .cache, action: .delete, locations: [], owner: owner, requiresFullDiskAccess: installed, itemByItem: true),
            CleanupRule(id: proxyMediaID, category: .photoVideo, title: "Final Cut Pro proxy media",
                        detail: "Lightweight copies of your media for editing inside each library, not any stored outside one.",
                        consequence: onlyCopy, regen: .cache, action: .delete, locations: [], owner: owner, requiresFullDiskAccess: installed, itemByItem: true),
        ]
    }

    /// The entry called exactly `name` in `folder` (never another case of it), when it is a real folder.
    static func realFolder(named name: String, in folder: URL) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path), names.contains(name) else { return nil }
        let url = folder.appendingPathComponent(name)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return url
    }

    /// The folders a rule's folder sits in, one per event: the event itself, or its `Transcoded Media`.
    static func parents(of ruleID: String, in library: URL) -> [(event: String, folder: URL)] {
        guard let path = layout[ruleID], let names = try? FileManager.default.contentsOfDirectory(atPath: library.path) else { return [] }
        return names.sorted().filter { !$0.hasPrefix(".") }.compactMap { name in
            guard let event = realFolder(named: name, in: library) else { return nil }
            return path.dropLast().reduce(Optional(event)) { folder, part in folder.flatMap { realFolder(named: part, in: $0) } }.map { (name, $0) }
        }
    }

    /// The rule's folder in each event of `library`.
    static func folders(of ruleID: String, in library: URL) -> [(event: String, url: URL)] {
        guard let name = layout[ruleID]?.last else { return [] }
        return parents(of: ruleID, in: library).compactMap { event, parent in realFolder(named: name, in: parent).map { (event, $0) } }
    }

    /// The check just before acting: the item must still be its rule's folder, or a deletion remnant of it, at its documented
    /// place in the library it was found in. Nil when it may go.
    static func refusal(for candidate: Candidate, root: URL) -> CheckRefusal? {
        guard root.pathExtension.lowercased() == libraryExtension else { return .changed }
        let places = candidate.isDeletionRemnant ? parents(of: candidate.ruleID, in: root).map(\.folder) : folders(of: candidate.ruleID, in: root).map(\.url)
        let target = (candidate.isDeletionRemnant ? candidate.url.deletingLastPathComponent() : candidate.url).standardizedFileURL.path
        return places.contains { $0.standardizedFileURL.path == target } ? nil : .changed
    }
}

extension Catalog {
    /// A Final Cut rule's folders and deletion remnants in each library, named "<library> · <event>", grouped by library and
    /// scoped to it.
    func finalCutGeneratedMedia(_ rule: CleanupRule, in libraries: [URL], sizer: KnownLocationSizer) -> [Candidate] {
        libraries.flatMap { library -> [Candidate] in
            let name = library.deletingPathExtension().lastPathComponent
            let folders = FinalCutGeneratedMedia.folders(of: rule.id, in: library).map { ($0.event, $0.url) }
            let remnants = FinalCutGeneratedMedia.parents(of: rule.id, in: library).flatMap { event, parent in
                ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []).sorted()
                    .filter { Self.isDeletionRemnant($0, of: rule.id) }.map { (event, parent.appendingPathComponent($0)) }
            }
            return (folders + remnants).compactMap { event, url -> Candidate? in
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR, ScopeContainment.contains(url, in: library),
                      Protection(rule).protectedComponent(of: url, below: library) == nil, CandidateCheck.protectedEntry(in: url, rule: rule) == nil else { return nil }
                let size = sizer.size(url)
                var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil, profile: name)
                found.itemName = name + " · " + event
                return found.found(under: library)
            }
        }
    }
}
