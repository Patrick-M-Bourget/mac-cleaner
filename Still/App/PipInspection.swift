import SwiftUI
import AppKit
import StillCore

@MainActor final class PipInspection: ObservableObject {
    @Published private(set) var python: URL?
    @Published private(set) var cache: URL?
    @Published private(set) var inventory: PipInventory?
    @Published private(set) var status = "Choose an interpreter and cache explicitly. No tools or home caches are probed automatically."
    @Published private(set) var inspecting = false
    @Published private(set) var isReference = false
    func choose(isCache: Bool) {
        let panel = NSOpenPanel()
        panel.title = isCache ? "Choose pip cache folder" : "Choose Python interpreter"
        panel.canChooseFiles = !isCache; panel.canChooseDirectories = isCache; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isCache { cache = url } else { python = url }
        inventory = nil; isReference = false
        status = "Choices recorded. Inspect verifies qualification before invoking a tool."
    }
    func inspect() async {
        guard let python, let cache, !inspecting else { return }
        inspecting = true; isReference = false
        defer { inspecting = false }
        let result: Result<PipCacheReport, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Result { try PipInventoryInspector.inspectSelected(python: python, cache: cache) })
            }
        }
        switch result {
        case .success(let report): inventory = report.inventory; status = "Selected installation remains unqualified. No commands were run; no cleanup is enabled."
        case .failure: inventory = nil; status = "Interpreter or cache unavailable. Rechoose the paths; Still will not install packages or request elevated access."
        }
    }
    func showReference() {
        python = nil; cache = nil; isReference = true
        inventory = PipInventory.parse(versionOutput: "pip 21.2.4 from /disposable/venv/site-packages/pip (python 3.9)", configuredCache: "/disposable/alternate-cache", cacheInfo: "Package index page cache location: /disposable/alternate-cache/http\nPackage index page cache size: 0 bytes\nNumber of HTTP files: 0\nWheels location: /disposable/alternate-cache/wheels\nWheels size: 29 bytes\nNumber of wheels: 1", wheelList: "/disposable/alternate-cache/wheels/still_fixture-1.0-py3-none-any.whl")
        status = "Recorded disposable qualification reference. Paths are redacted examples; the 29-byte cache seed was synthetic. Your environment has not been inspected."
    }
}

struct PipInspectionView: View {
    @StateObject private var model = PipInspection()
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            Text("pip cache opportunities").font(.largeTitle.weight(.semibold))
            Text("Read-only inventory qualification · Future milestone").foregroundStyle(.secondary)
            Text("A genuine disposable Python 3.9 / pip 21.2.4 environment passed inventory checks. Other installations still require provenance and unchanged-state qualification.")
            HStack {
                Button("Choose Python interpreter…") { model.choose(isCache: false) }
                Button("Choose cache folder…") { model.choose(isCache: true) }
                Button("Inspect selected pip cache") { Task { await model.inspect() } }.disabled(model.python == nil || model.cache == nil || model.inspecting)
            }.disabled(model.inspecting)
            if let python = model.python { Text("Interpreter: \(python.path)").font(.caption).textSelection(.enabled) }
            if let cache = model.cache { Text("Chosen cache: \(cache.path)").font(.caption).textSelection(.enabled) }
            Text(model.status).accessibilityIdentifier("pipInventoryStatus")
            if let inventory = model.inventory {
                Text(model.isReference ? "Recorded disposable evidence" : "Qualification evidence").font(.headline)
                Text("Version: \(inventory.version)")
                Text("Reported cache: \(inventory.cache)").textSelection(.enabled)
                if let guidance = inventory.guidance { Text(guidance).foregroundStyle(.secondary) }
                if !inventory.cacheInfo.isEmpty {
                    Text("Tool-reported summary · Not exclusive reclaimable bytes").font(.headline)
                    Text(inventory.cacheInfo).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Wheel list covers wheel caches only; HTTP response contents are not listed. Allocated bytes for this recorded reference: Unknown.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(inventory.wheels, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
            }
            Divider()
            Button("Show recorded disposable qualification") { model.showReference() }
            Text("No package install or cache mutation is available here. Genuine bootstrap occurs only in owned test environments; ordinary inventory never bootstraps an interpreter.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
