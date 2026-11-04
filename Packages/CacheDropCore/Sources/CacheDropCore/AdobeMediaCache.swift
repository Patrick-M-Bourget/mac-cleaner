import Foundation
import Darwin

/// Adobe's media cache moved in Settings › Media Cache (#730, Decision 163). Premiere Pro, After Effects and Media Encoder share
/// one media cache: conformed audio and index files in `Media Cache Files`, the database linking them in `Media Cache`, and audio
/// peak files in `Peak Files` (Adobe Help, "Manage media cache": "accelerator files, including peak files (.pek) and conformed
/// audio (.cfa)"; Media Encoder Help, "Media cache database": the files and the database can be moved separately, and the cache
/// is "shared with Adobe Media Encoder, Adobe Premiere, and After Effects"). Deleted files "are recreated automatically whenever
/// source media requires them" (Adobe Help, "Clear media cache using preferences").
///
/// Where a moved cache is isn't documented. Observed on Premiere Pro 26.0 (#400): `~/Library/Preferences/com.Adobe.Common
/// <version>.plist` holds a `Media Cache` dictionary whose `FolderPath` and `DatabasePath` name the chosen folders, absent until
/// the user moves the cache, and Adobe makes the same three folders inside the chosen one. After a move Premiere still writes to
/// the default folder too, so both are offered. Only those three folders are ever offered from a moved location, never the
/// folder the user chose or anything else in it, so it may be on any local drive; one on a network drive or in iCloud Drive is left out.
public enum AdobeMediaCache {
    static let ruleID = "adobe-media-cache"
    /// The default media cache location, under the home folder.
    static let defaultFolder = "Library/Application Support/Adobe/Common"
    /// The folders Adobe makes in a media cache location; nothing else there is ever offered.
    static let cacheFolders = ["Media Cache Files", "Media Cache", "Peak Files"]
    /// Shown on an item, as tool-named folders show theirs (#206).
    static let movedSource = "Set in Adobe settings"
    static let defaultSource = "Default location"
    /// The settings files, one per version: `com.Adobe.Common 26.0.plist`.
    static let settingsPrefix = "com.Adobe.Common ", settingsFolder = "Library/Preferences"
    /// A settings file larger than this isn't Adobe's few keys, and isn't read.
    static let settingsLimit = 1_000_000

    /// What the settings files name as moved media cache folders.
    struct Settings: Equatable {
        /// Each folder named once, in file and key order, without the default folder.
        var folders: [URL] = []
        /// A settings file that names a moved cache couldn't be read, or names it in a way that can't be followed.
        var unreadable = false
    }

    /// Reads `FolderPath` and `DatabasePath` from every version's settings file. Nothing is guessed: a file that can't be parsed,
    /// or a value that isn't an absolute path, makes the moved cache unreadable rather than pointing anywhere.
    static func settings(home: URL) -> Settings {
        var result = Settings()
        let folder = home.appendingPathComponent(settingsFolder)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter {
            $0.lowercased().hasPrefix(settingsPrefix.lowercased()) && $0.lowercased().hasSuffix(".plist")
        }.sorted()
        let usual = home.appendingPathComponent(defaultFolder).standardizedFileURL.path
        var seen: Set<String> = [usual]
        for name in names {
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            guard info.st_size < settingsLimit, let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { result.unreadable = true; continue }
            guard let cache = plist["Media Cache"] else { continue }
            guard let cache = cache as? [String: Any] else { result.unreadable = true; continue }
            for key in ["FolderPath", "DatabasePath"] {
                guard let value = cache[key] else { continue }
                guard let path = value as? String, let moved = CacheConfig.folder(path, home: home) else { result.unreadable = true; continue }
                if seen.insert(moved.standardizedFileURL.path).inserted { result.folders.append(moved) }
            }
        }
        return result
    }

    /// Where a moved folder is, as the plan explains it.
    enum Place: Equatable { case local, network, notConnected, missing, iCloud }

    /// Whether `folder` is on a local drive; nil when that can't be read.
    static func isLocal(_ folder: URL) -> Bool? {
        (try? folder.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal
    }

    /// Whether `folder` syncs with iCloud Drive (a Desktop or Documents folder in iCloud); deleting there would delete it everywhere.
    static func isInICloud(_ folder: URL) -> Bool {
        (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    static func place(of folder: URL, isLocal: (URL) -> Bool? = AdobeMediaCache.isLocal, isInICloud: (URL) -> Bool = AdobeMediaCache.isInICloud) -> Place {
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            // A folder on a drive that isn't mounted: `/Volumes/<name>` itself is gone.
            let parts = folder.standardizedFileURL.pathComponents
            if parts.count > 2, parts[1] == "Volumes", lstat("/Volumes/" + parts[2], &info) != 0 { return .notConnected }
            return .missing
        }
        // A drive whose kind can't be read is treated as a network drive: left out, never guessed.
        guard isLocal(folder) == true else { return .network }
        // CacheDrop never deletes what iCloud stores (SPEC section 2), so a cache there is explained once, not skipped item by item.
        return isInICloud(folder) ? .iCloud : .local
    }

    /// The plan's note for a moved folder nothing is offered from; nil for a local one.
    static func note(_ place: Place, shown: String) -> String? {
        let says = "Adobe settings name \(shown) as the media cache"
        switch place {
        case .local: return nil
        case .network: return "\(says), which is on a network drive, so it isn’t offered."
        case .iCloud: return "\(says), which is in iCloud Drive, so it isn’t offered."
        case .notConnected: return "\(says), which is on a drive that isn’t connected, so it isn’t offered."
        case .missing: return "\(says), but there’s no folder there, so it isn’t offered."
        }
    }
    static let unreadableNote = "CacheDrop couldn’t read Adobe’s media cache settings, so a moved media cache isn’t offered."

    /// The check just before acting, for an item from a moved folder (`root`, the folder the settings named at the scan): it must
    /// still be one of Adobe's folders right inside it, the settings must still name it, and it must be on a local drive.
    /// Items in the default folder are scoped to the home folder and pass through. Nil when it may go.
    static func refusal(for candidate: Candidate, root: URL, home: URL, isLocal: (URL) -> Bool? = AdobeMediaCache.isLocal) -> CheckRefusal? {
        let parent = candidate.url.deletingLastPathComponent().standardizedFileURL.path
        if parent == root.appendingPathComponent(defaultFolder).standardizedFileURL.path { return nil }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard cacheFolders.contains(candidate.url.lastPathComponent),
              parent == root.standardizedFileURL.path else { return .changed }
        let named = settings(home: home).folders.contains { $0.resolvingSymlinksInPath().standardizedFileURL.path == rootPath }
        guard named else { return .notACache("Adobe settings no longer name this folder, so it is kept.") }
        guard isLocal(root) == true else { return .notACache("It is on a network drive, so it is kept.") }
        return nil
    }
}

extension Catalog {
    /// The media cache folders in each moved location the settings name, scoped to that location, and a note for each location
    /// nothing is offered from. The rule's default folder is found as its other locations are.
    func movedAdobeMediaCaches(_ rule: CleanupRule, home: URL, sizer: KnownLocationSizer, isLocal: (URL) -> Bool? = AdobeMediaCache.isLocal,
                               isInICloud: (URL) -> Bool = AdobeMediaCache.isInICloud) -> (candidates: [Candidate], notes: [CatalogNote]) {
        let settings = AdobeMediaCache.settings(home: home)
        var notes = settings.unreadable ? [CatalogNote(ruleID: rule.id, text: AdobeMediaCache.unreadableNote)] : []
        var candidates: [Candidate] = []
        for folder in settings.folders {
            let place = AdobeMediaCache.place(of: folder, isLocal: isLocal, isInICloud: isInICloud)
            if let text = AdobeMediaCache.note(place, shown: Self.tildePath(folder, base: home)) { notes.append(CatalogNote(ruleID: rule.id, text: text)); continue }
            for name in AdobeMediaCache.cacheFolders {
                let url = folder.appendingPathComponent(name)
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
                      ScopeContainment.contains(url, in: folder), Protection(rule).protectedComponent(of: url, below: folder) == nil,
                      CandidateCheck.protectedEntry(in: url, rule: rule) == nil else { continue }
                let size = sizer.size(url)
                var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
                found.folderSource = AdobeMediaCache.movedSource
                candidates.append(found.found(under: folder))
            }
        }
        return (candidates, notes)
    }
}
