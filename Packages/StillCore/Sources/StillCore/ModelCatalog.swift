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
        // Installed by pip, both run as `python …/bin/hf`, so the script is matched as well as the executable.
        owner: RuleOwner(name: "Hugging Face CLI", executables: ["huggingface-cli", "hf"], scripts: ["huggingface-cli", "hf"]),
        itemName: { name in
            guard name.hasPrefix("models--") else { return nil }
            return name.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
        })
    /// Ollama's own server must be running for `ollama rm`, so the rule has no owner to close.
    static let ollamaModels = CleanupRule(
        id: "ollama-models", category: .models, title: "Ollama models",
        detail: "Models Ollama downloaded. Sizes count only the files no other model shares. Check when each was last used.",
        consequence: "Runs `ollama rm` for each model, which permanently removes it and any files no other model uses. Run `ollama pull` to download it again. Ollama must be open.",
        regen: .model, action: .tool, locations: [".ollama/models/manifests"], owner: nil,
        tool: ToolCommand(executables: ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"],
                          arguments: ["rm", "<model>"], timeout: 120, itemPlaceholder: "<model>"),
        items: .ollamaModels)
    /// Field note section 6: Claude's VM keeps `rootfs.img` (10 GB) unpacked beside `rootfs.img.zst` (1.1 GB).
    /// Only that unpacked copy is offered, only in the app's own VM folder, and only while the app is closed.
    /// The rule may act inside the app's `.bundle` folder; sparse bundles and every other protected kind stay protected.
    static let appVMImages = CleanupRule(
        id: "app-vm-images", category: .models, title: "Unpacked VM disk images",
        detail: "Disk images an app unpacked from a compressed copy it keeps beside them. Check when each was last used.",
        consequence: "Moved to Trash. The compressed copy stays, and the app unpacks or downloads the image again when it next needs it. Quit the app first.",
        regen: .model, action: .trash, locations: ["Library/Application Support/Claude/vm_bundles/*"],
        owner: RuleOwner(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"]),
        contents: ContentsMatch(minimumBytes: 100_000_000, besideCompressedSource: true),
        unprotectedExtensions: ["bundle"])
}

/// Where a rule's items come from when they aren't folders or files matched by name.
public enum CatalogItems: Sendable, Equatable {
    /// One item per model manifest under Ollama's `models/manifests`; Ollama itself is never run to list them.
    case ollamaModels
    /// One item per prune kind, sized by what `docker system df` says Docker can reclaim.
    case docker(DockerPruneKind)
}

private struct OllamaManifest: Decodable {
    struct Layer: Decodable { let digest: String; let size: Int64 }
    let config: Layer?
    let layers: [Layer]
}

extension Catalog {
    static let compressedSourceExtensions = ["zst", "gz", "xz", "lz4", "bz2"]
    /// Whether a smaller regular file of ours named `<file>.<compression>` sits beside `url`.
    static func hasCompressedSource(_ url: URL, size: Int64) -> Bool {
        compressedSourceExtensions.contains { ext in
            var info = stat()
            return lstat(url.path + "." + ext, &info) == 0 && info.st_mode & S_IFMT == S_IFREG && info.st_uid == geteuid() && Int64(info.st_size) < size
        }
    }

    /// One candidate per model manifest (`<host>/<namespace>/<model>/<tag>`). The size is an estimate: only blobs
    /// no other manifest references, since `ollama rm` keeps shared ones.
    func ollamaModels(in manifests: URL, rule: CleanupRule, toolURL: URL?) -> [Candidate] {
        let blobs = manifests.deletingLastPathComponent().appendingPathComponent("blobs")
        var parsed: [(url: URL, info: stat, name: String?, layers: [OllamaManifest.Layer])] = []
        guard FileTree.walk(manifests, { entry in
            guard parsed.count < Self.childLimit else { return .stop }
            let level = Int(entry.pointee.fts_level)
            if Int32(entry.pointee.fts_info) == FTS_D, level >= 4 { return .skip }
            guard Int32(entry.pointee.fts_info) == FTS_F, level == 4, let info = entry.pointee.fts_statp?.pointee,
                  info.st_uid == geteuid(), info.st_size <= 1_000_000 else { return .continue }
            let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
            guard let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(OllamaManifest.self, from: data) else { return .continue }
            let parts = Array(url.pathComponents.suffix(4))
            parsed.append((url, info, Self.ollamaName(parts), (manifest.config.map { [$0] } ?? []) + manifest.layers))
            return .continue
        }) else { return [] }
        // Every readable manifest counts toward sharing, even one that isn't offered.
        var references: [String: Int] = [:]
        for model in parsed { for digest in Set(model.layers.map(\.digest)) { references[digest, default: 0] += 1 } }
        return parsed.compactMap { model in
            guard let name = model.name else { return nil }
            var seen = Set<String>()
            let own = model.layers.filter { seen.insert($0.digest).inserted && references[$0.digest] == 1 }.reduce(Int64(0)) { $0 + max($1.size, 0) }
            var lastUsed = Self.lastUsed(model.url, model.info)
            if let largest = model.layers.max(by: { $0.size < $1.size }) {
                let blob = blobs.appendingPathComponent(largest.digest.replacingOccurrences(of: ":", with: "-"))
                var info = stat()
                if lstat(blob.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG { lastUsed = max(lastUsed, Self.lastUsed(blob, info)) }
            }
            var found = candidate(rule, model.url, model.info, logical: own, allocated: nil, complete: true, lastUsed: lastUsed, toolURL: toolURL)
            found.itemName = name; found.sizeIsEstimate = true; found.fileBytes = Int64(model.info.st_size)
            return found
        }
    }

    /// The name `ollama rm` takes: `llama3:latest`, `someone/tuned:v2`, or `hf.co/org/repo:tag` for other registries.
    /// Nil unless every part is a plain name, so nothing read from disk can become an option.
    static func ollamaName(_ parts: [String]) -> String? {
        guard parts.count == 4, parts.allSatisfy({ part in
            part.first.map { $0.isLetter || $0.isNumber } == true && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        }) else { return nil }
        let (host, namespace, model, tag) = (parts[0], parts[1], parts[2], parts[3])
        if host == "registry.ollama.ai" { return (namespace == "library" ? "" : namespace + "/") + model + ":" + tag }
        return host + "/" + namespace + "/" + model + ":" + tag
    }

    /// Conservative "last used" for a folder: the latest of Spotlight's last-opened date for the folder and
    /// the access, change and creation times of the files inside. Folder access times are left out,
    /// because listing a folder (as sizing does) updates them.
    static func lastUsedInside(_ url: URL, _ info: stat) -> Date {
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9) }
        var newest = [date(info.st_mtimespec), date(info.st_birthtimespec)].max()!
        if let item = MDItemCreateWithURL(nil, url as CFURL), let opened = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { newest = max(newest, opened) }
        FileTree.walk(url) { entry in
            guard let entryInfo = entry.pointee.fts_statp?.pointee else { return .continue }
            switch Int32(entry.pointee.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE:
                newest = max(newest, date(entryInfo.st_atimespec), date(entryInfo.st_mtimespec), date(entryInfo.st_birthtimespec))
            case FTS_D:
                newest = max(newest, date(entryInfo.st_mtimespec), date(entryInfo.st_birthtimespec))
            default: break
            }
            return .continue
        }
        return newest
    }
}
