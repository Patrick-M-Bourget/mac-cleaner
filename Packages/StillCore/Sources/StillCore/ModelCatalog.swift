import Foundation
import Darwin

/// ML models and app disk images (#104). Models and images go to Trash (Decision 3); Ollama models
/// go through `ollama rm`, because their blobs are shared between models (Decision 19).
extension BuiltInCatalog {
    static let huggingFaceModels = CleanupRule(
        id: "huggingface-models", category: .models, title: "Hugging Face models",
        detail: "Models downloaded to the Hugging Face cache. Check when each was last used.",
        consequence: "Moved to Trash. You can restore them from the Trash; otherwise they download again the next time a project uses them.",
        regen: .model, action: .trash, locations: [".cache/huggingface/hub/models--*"],
        owner: RuleOwner(name: "Hugging Face CLI", executables: ["huggingface-cli", "hf"]),
        itemName: { name in
            guard name.hasPrefix("models--") else { return nil }
            return name.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
        })
}

extension Catalog {
    /// Conservative "last used" for a folder: the latest of Spotlight's last-opened date for the folder and
    /// the access, change and creation times of the files inside. Folder access times are left out,
    /// because listing a folder (as sizing does) updates them.
    static func lastUsedInside(_ url: URL, _ info: stat) -> Date {
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9) }
        var newest = [date(info.st_mtimespec), date(info.st_birthtimespec)].max()!
        if let item = MDItemCreateWithURL(nil, url as CFURL), let opened = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { newest = max(newest, opened) }
        let path = strdup(url.path)
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return newest }
        defer { fts_close(tree) }
        while let entry = fts_read(tree) {
            guard let entryInfo = entry.pointee.fts_statp?.pointee else { continue }
            switch Int32(entry.pointee.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE:
                newest = max(newest, date(entryInfo.st_atimespec), date(entryInfo.st_mtimespec), date(entryInfo.st_birthtimespec))
            case FTS_D:
                newest = max(newest, date(entryInfo.st_mtimespec), date(entryInfo.st_birthtimespec))
            default: continue
            }
        }
        return newest
    }
}
