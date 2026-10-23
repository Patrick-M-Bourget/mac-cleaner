import SwiftUI
import AppKit
import Darwin
import StillCore

@MainActor final class HomebrewInspection: ObservableObject {
    @Published private(set) var executable: URL?
    @Published private(set) var report: HomebrewPreview?
    @Published private(set) var cache: URL?
    @Published private(set) var inventory: HomebrewCacheInventory?
    @Published private(set) var status = "Choose Homebrew and its cache explicitly. No installed code, configuration or personal cache is probed automatically."
    @Published private(set) var inspecting = false
    @Published private(set) var isExample = false
    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--homebrew-inventory-fixture"),
           let path = ProcessInfo.processInfo.environment["STILL_TEST_HOMEBREW_ROOT"],
           let expectedID = ProcessInfo.processInfo.environment["STILL_TEST_HOMEBREW_ROOT_ID"] {
            let selected = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
            let runnerTemporary = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.patrickbourget.StillUITests.xctrunner/Data/tmp")
                .standardizedFileURL.resolvingSymlinksInPath()
            var information = stat()
            if [temporary, runnerTemporary].contains(selected.deletingLastPathComponent()),
               selected.lastPathComponent.hasPrefix("StillHomebrewUI-"),
               UUID(uuidString: String(selected.lastPathComponent.dropFirst("StillHomebrewUI-".count))) != nil,
               lstat(selected.path, &information) == 0, information.st_mode & S_IFMT == S_IFDIR, information.st_uid == geteuid(),
               "\(information.st_dev):\(information.st_ino)" == expectedID {
                executable = selected.appendingPathComponent("source/bin/brew")
                cache = selected.appendingPathComponent("cache")
                status = "Disposable source and cache selected. Inspect explicitly; installed code is never executed."
            } else {
                status = "Disposable fixture rejected: canonical temporary scope or resource identity did not match."
            }
        }
#endif
    }
    func chooseExecutable(isCache: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = isCache ? "Choose Homebrew cache folder" : "Choose Homebrew executable"
        panel.message = isCache ? "This explicitly overrides Homebrew cache settings. Still does not discover or read brew.env." : "Supports pinned Homebrew 4.6.17 shell sources only. Installed code is never executed."
        panel.canChooseDirectories = isCache; panel.canChooseFiles = !isCache; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isCache { cache = url } else { executable = url }; report = nil; inventory = nil; isExample = false
        status = "Executable selected. Inspect checks qualification before running any tool."
    }
    func inspect() async {
        guard let executable, let cache, !inspecting else { return }
        inspecting = true; isExample = false; report = nil; inventory = nil
        status = "Verifying pinned shell sources and inspecting the selected cache…"
        defer { inspecting = false }
        let result: Result<HomebrewCacheInventory, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Result { try HomebrewInspector.inspectSelected(executable: executable, cache: cache) })
            }
        }
        switch result {
        case .success(let result):
            inventory = result
            status = result.supported ? (result.complete ? "Read-only cache inventory complete. No cleanup is available." : "Partial cache inventory. Totals are unknown; no cleanup is available.") : result.guidance
        case .failure(let error):
            switch error as? ToolPreviewError {
            case .timeout: status = "Inspection timed out. Choose a smaller cache and retry explicitly. No cleanup is available."
            case .outputLimit: status = "Inspection exceeded a bounded output limit. Retry explicitly; no cleanup is available."
            default: status = "Inspection unavailable: source provenance or cache access could not be verified. Rechoose the paths; Still never installs tools or requests elevated access."
            }
        }
    }
    func showExample() {
        isExample = true
        executable = nil; cache = nil; inventory = nil
        report = HomebrewPreview.parse(version: "Homebrew fixture-1", prefix: "/disposable/prefix", cache: "/disposable/cache", output: "Would remove: /disposable/cache/archive (12.3MB)\nWould free: 12.3MB", qualifiedVersion: "Homebrew fixture-1")
        status = "Disposable example only. These paths and estimates are synthetic; no installed tool was inspected."
    }
}

struct HomebrewInspectionView: View {
    @StateObject private var model = HomebrewInspection()
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            PageHeader(title: "Homebrew opportunities")
            Text("Read-only Homebrew cache inventory").foregroundStyle(.secondary)
            Text("Supports pinned Homebrew 4.6.17 shell sources. Still inspects your chosen cache without running installed code, reading brew.env or loading formulae. Vendor cleanup remains unqualified.")
            SettingsRow(title: "Selected installation") {
            HStack {
                Button("Choose Homebrew executable…") { model.chooseExecutable() }.disabled(model.inspecting)
                Button("Choose cache folder…") { model.chooseExecutable(isCache: true) }.disabled(model.inspecting)
                Button("Inspect selected Homebrew") { Task { await model.inspect() } }.disabled(model.executable == nil || model.cache == nil || model.inspecting)
            }
            }
            if let executable = model.executable { Text("Installation: \(executable.path)").textSelection(.enabled).font(.caption) }
            if let cache = model.cache { Text("Explicit cache override: \(cache.path)").textSelection(.enabled).font(.caption) }
            StatusRow(text: model.status, symbol: "info.circle", identifier: "homebrewPreviewStatus")
            if let inventory = model.inventory {
                if inventory.supported {
                SummarySurface {
                    VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                        Text("Observed regular files: \(inventory.regularFileCount)").font(.headline)
                        Text("Logical bytes: \(inventory.logicalBytes.map(String.init) ?? "Unknown")")
                        Text("Allocated bytes: \(inventory.allocatedBytes.map(String.init) ?? "Unknown")")
                        Text("Download files: \(inventory.downloadFileCount) · Top-level incomplete files: \(inventory.incompleteDownloadCount)")
                        Text("Reclaimable space: Unknown").foregroundStyle(.secondary)
                        Text("Observed: \(inventory.observedAt.formatted())").font(.caption)
                    }
                }
                }
                Text(inventory.version).font(.headline)
                Text("Resolved installation prefix: \(inventory.prefix)").font(.caption).textSelection(.enabled)
                Text("Queried explicit cache: \(inventory.cache)").font(.caption).textSelection(.enabled)
                Text(inventory.guidance).font(.caption).foregroundStyle(.secondary)
                if !inventory.incompleteDownloads.isEmpty {
                    Text("Incomplete download names · May still be active").font(.headline)
                    ForEach(Array(inventory.incompleteDownloads.prefix(20).enumerated()), id: \.offset) { _, entry in
                        Text("\(entry.relativePath) · \(entry.logicalBytes) logical bytes").font(.caption).textSelection(.enabled)
                    }
                    if inventory.incompleteDownloadCount > 20 { Text("Showing up to 20 names; counts include all observed files.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let report = model.report {
                Text(model.isExample ? "Synthetic preview evidence" : "Tool evidence").font(.headline)
                Text("Version: \(report.version)")
                Text("Configured prefix: \(report.prefix)").textSelection(.enabled)
                Text("Configured cache: \(report.cache)").textSelection(.enabled)
                if let guidance = report.guidance { Text(guidance).foregroundStyle(.secondary) }
                if !report.targets.isEmpty {
                    Text("Reported candidates").font(.headline)
                    ForEach(Array(report.targets.enumerated()), id: \.offset) { _, target in Text(target).textSelection(.enabled) }
                    Text("Tool-reported estimate: \(report.estimate ?? "Unknown") · Not guaranteed reclaimed space").foregroundStyle(.secondary)
                }
            }
            Divider()
            Button("Show disposable preview example") { model.showExample() }.disabled(model.inspecting)
            Text("The example below uses synthetic vendor-format output. Real cache inventory measures metadata only; it does not predict brew cleanup or authorize deletion.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
