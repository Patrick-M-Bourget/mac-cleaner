import SwiftUI
import AppKit
import Darwin
import CacheDropCore

@MainActor final class PipInspection: ObservableObject {
    @Published private(set) var python: URL?
    @Published private(set) var cache: URL?
    @Published private(set) var inventory: PipInventory?
    @Published private(set) var report: PipCacheReport?
    @Published private(set) var status = "Choose an interpreter and cache explicitly. No tools or home caches are probed automatically."
    @Published private(set) var inspecting = false
    @Published private(set) var isReference = false
    func choose(isCache: Bool) {
        let panel = NSOpenPanel()
        panel.title = isCache ? "Choose pip cache folder" : "Choose Apple developer tools Python"
        panel.message = isCache ? "Choose the exact cache to inspect. CacheDrop overrides pip’s configured cache for this read-only inventory." : "Only Apple-signed Command Line Tools Python with its bundled pip is supported. Other interpreters are never executed."
        if !isCache { panel.directoryURL = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin") }
        panel.canChooseFiles = !isCache; panel.canChooseDirectories = isCache; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isCache { cache = url } else { python = url }
        inventory = nil; report = nil; isReference = false
        status = "Choices recorded. Inspect verifies the Apple signature before invoking a tool."
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
            status = result.inventory.supported ? "Read-only inventory complete. Apple signature verified. Only the chosen cache was requested; no cleanup is enabled." : "Selected installation is unsupported. Only Apple developer tools Python and its bundled pip are supported; other interpreters are not executed."
        case .failure(let error):
            inventory = nil; report = nil
            switch error as? ToolPreviewError {
            case .timeout: status = "Inventory timed out. Choose a smaller cache and retry explicitly; no cleanup is enabled."
            case .outputLimit: status = "Inventory exceeded a bounded metadata or output limit. Choose a smaller cache and retry explicitly; no cleanup is enabled."
            default: status = "Inventory unavailable: interpreter provenance, cache access or output could not be verified. Rechoose the paths; CacheDrop never installs packages or requests elevated access."
            }
        }
    }
    func showReference() {
        python = nil; cache = nil; report = nil; isReference = true
        inventory = PipInventory.parse(versionOutput: "pip 21.2.4 from /disposable/venv/site-packages/pip (python 3.9)", configuredCache: "/disposable/alternate-cache", cacheInfo: "Package index page cache location: /disposable/alternate-cache/http\nPackage index page cache size: 0 bytes\nNumber of HTTP files: 0\nWheels location: /disposable/alternate-cache/wheels\nWheels size: 29 bytes\nNumber of wheels: 1", wheelList: "/disposable/alternate-cache/wheels/cachedrop_fixture-1.0-py3-none-any.whl")
        status = "Recorded disposable qualification reference. Paths are redacted examples; the 29-byte cache seed was synthetic. Your environment has not been inspected."
    }
}

struct PipInspectionView: View {
    @StateObject private var model = PipInspection()
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "pip cache opportunities", back: BackButton(destination: Destination.overview.rawValue, action: back))
            Text("Read-only cache inventory").foregroundStyle(.secondary)
            Text("Supports Apple developer tools Python with its bundled pip. CacheDrop verifies Apple signatures and the bundled tool before running read-only commands. Other interpreters are not executed.")
            SettingsRow(title: "Selected installation") {
            HStack {
                Button("Choose Python interpreter…") { model.choose(isCache: false) }
                Button("Choose cache folder…") { model.choose(isCache: true) }
                Button("Inspect selected pip cache") { Task { await model.inspect() } }.disabled(model.python == nil || model.cache == nil || model.inspecting)
            }.disabled(model.inspecting)
            }
            if let python = model.python { Text("Interpreter: \(python.path)").font(CacheDropDesign.TypeStyle.caption).textSelection(.enabled) }
            if let cache = model.cache { Text("Chosen cache: \(cache.path)").font(CacheDropDesign.TypeStyle.caption).textSelection(.enabled) }
            StatusRow(text: model.status, symbol: "info.circle", identifier: "pipInventoryStatus")
            if let inventory = model.inventory {
                Text(model.isReference ? "Recorded disposable evidence" : "Inventory evidence").font(.headline)
                if let report = model.report, inventory.supported {
                    SummarySurface {
                        VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                            Text("Listed wheels: \(report.wheels.count)").font(.headline)
                            Text("Wheel logical bytes: \(report.wheelLogicalBytes.map(String.init) ?? "Unknown")")
                            Text("Wheel allocated bytes: \(report.wheelAllocatedBytes.map(String.init) ?? "Unknown")")
                            Text("Observed: \(report.observedAt.formatted())").font(CacheDropDesign.TypeStyle.caption)
                            Text("Measurements are observed subtotals, not exclusive reclaimable space. Repeated hard-linked files may share allocations.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Version: \(inventory.version)")
                Text("Reported cache: \(inventory.cache)").textSelection(.enabled)
                if let guidance = inventory.guidance { Text(guidance).foregroundStyle(.secondary) }
                if !inventory.cacheInfo.isEmpty {
                    Text("Tool-reported summary · Not exclusive reclaimable bytes").font(.headline)
                    Text(inventory.cacheInfo).font(CacheDropDesign.TypeStyle.code).textSelection(.enabled)
                    Text(model.isReference ? "Wheel list covers wheel caches only; allocated bytes for this reference: Unknown." : "pip reports legacy http and wheels only. Newer http-v2 and other contents are unmeasured; total cache allocation: Unknown.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                }
                Text("\(inventory.wheels.count) listed wheel paths").font(CacheDropDesign.TypeStyle.caption)
                ForEach(Array(inventory.wheels.prefix(20)), id: \.self) { Text($0).font(CacheDropDesign.TypeStyle.caption).textSelection(.enabled) }
                if inventory.wheels.count > 20 { Text("Showing first 20 paths; measurements include all listed wheels.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary) }
            }
            Divider()
            Button("Show recorded disposable qualification") { model.showReference() }.disabled(model.inspecting)
            Text("No package install or cache mutation is available here. Genuine bootstrap occurs only in owned test environments; ordinary inventory never bootstraps an interpreter.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
        }
    }
}
