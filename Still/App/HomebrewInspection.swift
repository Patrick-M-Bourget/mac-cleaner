import SwiftUI
import AppKit
import StillCore

@MainActor final class HomebrewInspection: ObservableObject {
    @Published private(set) var executable: URL?
    @Published private(set) var report: HomebrewPreview?
    @Published private(set) var status = "Choose an executable explicitly. Still does not search your installation or cache."
    @Published private(set) var inspecting = false
    @Published private(set) var isExample = false
    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose Homebrew executable"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executable = url; report = nil; isExample = false
        status = "Executable selected. Inspect checks qualification before running any tool."
    }
    func inspect() async {
        guard let executable, !inspecting else { return }
        inspecting = true; isExample = false
        defer { inspecting = false }
        let result: Result<HomebrewPreview, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Result { try HomebrewInspector.inspect(executable: executable) })
            }
        }
        switch result {
        case .success(let preview): report = preview; status = "Qualification complete. No commands were run and no cleanup is available."
        case .failure: report = nil; status = "Tool unavailable or unsupported. Choose the Homebrew brew executable; Still will not install or elevate."
        }
    }
    func showExample() {
        isExample = true
        executable = nil
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
            Text("Read-only qualification preview").foregroundStyle(.secondary)
            Text("No released Homebrew version is qualified yet. Unknown tool behavior produces guidance; no cleanup or automatic tool invocation is enabled.")
            SettingsRow(title: "Selected installation") {
            HStack {
                Button("Choose Homebrew executable…") { model.chooseExecutable() }.disabled(model.inspecting)
                Button("Inspect selected Homebrew") { Task { await model.inspect() } }.disabled(model.executable == nil || model.inspecting)
            }
            }
            if let executable = model.executable { Text(executable.path).textSelection(.enabled).font(.caption) }
            StatusRow(text: model.status, symbol: "info.circle", identifier: "homebrewPreviewStatus")
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
            Button("Show disposable preview example") { model.showExample() }
            Text("The separate disposable helper tests validate bounded command arguments and fixture parsing. They do not qualify real Homebrew side effects or deletion semantics.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
