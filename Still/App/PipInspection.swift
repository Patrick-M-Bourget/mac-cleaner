import SwiftUI
import AppKit
import Darwin
import StillCore

@MainActor final class PipInspection: ObservableObject {
    @Published private(set) var python: URL?
    @Published private(set) var cache: URL?
    @Published private(set) var inventory: PipInventory?
    @Published private(set) var report: PipCacheReport?
    @Published private(set) var status = "Choose an interpreter and cache explicitly. No tools or home caches are probed automatically."
    @Published private(set) var inspecting = false
    @Published private(set) var isReference = false
    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--pip-inventory-fixture"),
           let path = ProcessInfo.processInfo.environment["STILL_TEST_PIP_CACHE"],
           let expectedID = ProcessInfo.processInfo.environment["STILL_TEST_PIP_CACHE_ID"] {
            let selected = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
            // XCTest's runner is sandboxed separately from this app. Accept only
            // its observed exact container tmp parent, never arbitrary containers.
            let runnerTemporary = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.patrickbourget.StillUITests.xctrunner/Data/tmp")
                .standardizedFileURL.resolvingSymlinksInPath()
            var information = stat()
            if [temporary, runnerTemporary].contains(selected.deletingLastPathComponent()),
               selected.lastPathComponent.hasPrefix("StillPipUI-"),
               UUID(uuidString: String(selected.lastPathComponent.dropFirst("StillPipUI-".count))) != nil,
               lstat(selected.path, &information) == 0, information.st_mode & S_IFMT == S_IFDIR, information.st_uid == geteuid(),
               "\(information.st_dev):\(information.st_ino)" == expectedID {
                python = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/python3")
                cache = selected
                status = "Disposable test cache selected. Inspect explicitly to run the verified bundled tool."
            } else {
                status = "Disposable fixture rejected: canonical temporary scope or resource identity did not match."
            }
        }
#endif
    }
    func choose(isCache: Bool) {
        let panel = NSOpenPanel()
        panel.title = isCache ? "Choose pip cache folder" : "Choose Apple developer tools Python"
        panel.message = isCache ? "Choose the exact cache to inspect. Still overrides pip’s configured cache for this read-only inventory." : "Only Apple-signed Command Line Tools Python 3.9 with its bundled pip 21.2.4 is supported. Other interpreters are never executed."
        if !isCache { panel.directoryURL = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin") }
        panel.canChooseFiles = !isCache; panel.canChooseDirectories = isCache; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isCache { cache = url } else { python = url }
        inventory = nil; report = nil; isReference = false
        status = "Choices recorded. Inspect verifies qualification before invoking a tool."
    }
    func inspect() async {
        guard let python, let cache, !inspecting else { return }
        inspecting = true; isReference = false; inventory = nil; report = nil
        status = "Verifying the supported tool and inspecting the explicit cache…"
        defer { inspecting = false }
        let result: Result<PipCacheReport, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Result { try PipInventoryInspector.inspectSelected(python: python, cache: cache) })
            }
        }
        switch result {
        case .success(let result):
            report = result; inventory = result.inventory
            status = result.inventory.supported ? "Read-only inventory complete. Apple signature and bundled pip digest verified. Only the chosen cache was requested; no cleanup is enabled." : "Selected installation is unsupported. Only Apple developer tools Python 3.9 and bundled pip 21.2.4 are supported; other interpreters are not executed."
        case .failure(let error):
            inventory = nil; report = nil
            switch error as? ToolPreviewError {
            case .timeout: status = "Inventory timed out. Choose a smaller cache and retry explicitly; no cleanup is enabled."
            case .outputLimit: status = "Inventory exceeded a bounded metadata or output limit. Choose a smaller cache and retry explicitly; no cleanup is enabled."
            default: status = "Inventory unavailable: interpreter provenance, cache access or output could not be verified. Rechoose the paths; Still never installs packages or requests elevated access."
            }
        }
    }
    func showReference() {
        python = nil; cache = nil; report = nil; isReference = true
        inventory = PipInventory.parse(versionOutput: "pip 21.2.4 from /disposable/venv/site-packages/pip (python 3.9)", configuredCache: "/disposable/alternate-cache", cacheInfo: "Package index page cache location: /disposable/alternate-cache/http\nPackage index page cache size: 0 bytes\nNumber of HTTP files: 0\nWheels location: /disposable/alternate-cache/wheels\nWheels size: 29 bytes\nNumber of wheels: 1", wheelList: "/disposable/alternate-cache/wheels/still_fixture-1.0-py3-none-any.whl")
        status = "Recorded disposable qualification reference. Paths are redacted examples; the 29-byte cache seed was synthetic. Your environment has not been inspected."
    }
}

struct PipInspectionView: View {
    @StateObject private var model = PipInspection()
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            PageHeader(title: "pip cache opportunities")
            Text("Read-only cache inventory").foregroundStyle(.secondary)
            Text("Supports Apple developer tools Python 3.9 with bundled pip 21.2.4. Still verifies Apple signatures and the bundled tool before running read-only commands. Other interpreters are not executed.")
            SettingsRow(title: "Selected installation") {
            HStack {
                Button("Choose Python interpreter…") { model.choose(isCache: false) }
                Button("Choose cache folder…") { model.choose(isCache: true) }
                Button("Inspect selected pip cache") { Task { await model.inspect() } }.disabled(model.python == nil || model.cache == nil || model.inspecting)
            }.disabled(model.inspecting)
            }
            if let python = model.python { Text("Interpreter: \(python.path)").font(.caption).textSelection(.enabled) }
            if let cache = model.cache { Text("Chosen cache: \(cache.path)").font(.caption).textSelection(.enabled) }
            StatusRow(text: model.status, symbol: "info.circle", identifier: "pipInventoryStatus")
            if let inventory = model.inventory {
                Text(model.isReference ? "Recorded disposable evidence" : "Inventory evidence").font(.headline)
                if let report = model.report, inventory.supported {
                    SummarySurface {
                        VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                            Text("Listed wheels: \(report.wheels.count)").font(.headline)
                            Text("Wheel logical bytes: \(report.wheelLogicalBytes.map(String.init) ?? "Unknown")")
                            Text("Wheel allocated bytes: \(report.wheelAllocatedBytes.map(String.init) ?? "Unknown")")
                            Text("Observed: \(report.observedAt.formatted())").font(.caption)
                            Text("Measurements are observed subtotals, not exclusive reclaimable space. Repeated hard-linked files may share allocations.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Version: \(inventory.version)")
                Text("Reported cache: \(inventory.cache)").textSelection(.enabled)
                if let guidance = inventory.guidance { Text(guidance).foregroundStyle(.secondary) }
                if !inventory.cacheInfo.isEmpty {
                    Text("Tool-reported summary · Not exclusive reclaimable bytes").font(.headline)
                    Text(inventory.cacheInfo).font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.isReference ? "Wheel list covers wheel caches only; allocated bytes for this reference: Unknown." : "pip 21.2.4 reports legacy http and wheels only. Newer http-v2 and other contents are unmeasured; total cache allocation: Unknown.").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(inventory.wheels.count) listed wheel paths").font(.caption)
                ForEach(Array(inventory.wheels.prefix(20)), id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                if inventory.wheels.count > 20 { Text("Showing first 20 paths; measurements include all listed wheels.").font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            Button("Show recorded disposable qualification") { model.showReference() }.disabled(model.inspecting)
            Text("No package install or cache mutation is available here. Genuine bootstrap occurs only in owned test environments; ordinary inventory never bootstraps an interpreter.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
