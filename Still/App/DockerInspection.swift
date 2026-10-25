import SwiftUI
import AppKit
import StillCore

@MainActor final class DockerInspection: ObservableObject {
    @Published private(set) var executable: URL?
    @Published private(set) var inventory: DockerInventory?
    @Published private(set) var image: DockerDiskImage?
    @Published var socketPath = "" {
        didSet {
            guard socketPath != oldValue else { return }
            inventory = nil; example = false
            status = "Socket changed. Inspect explicitly to read this endpoint. No command was run."
        }
    }
    @Published private(set) var status = "No Docker runtime has been inspected. Choose the supported CLI and enter a local Unix socket explicitly."
    @Published private(set) var busy = false
    @Published private(set) var example = false
    func chooseCLI() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose Docker CLI"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executable = url; inventory = nil; example = false
        status = "CLI selected. Inspect verifies its exact release hash before executing a private copy."
    }
    func inspectCLI() async {
        guard let executable, !socketPath.isEmpty, !busy else { return }
        guard socketPath.hasPrefix("/") else { inventory = nil; status = "Enter an absolute local Unix socket path beginning with /. No command was run."; return }
        busy = true; defer { busy = false }
        inventory = nil; example = false
        let socket = URL(fileURLWithPath: socketPath)
        let result: DockerInspector.Observation = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: DockerInspector.inspectSelected(executable: executable, socket: socket)) }
        }
        inventory = result.inventory; status = result.guidance
    }
    func chooseImage() async {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose disk image for metadata inspection"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; defer { busy = false }
        let result: Result<DockerDiskImage, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: Result { try DockerDiskImage.readSelected(url) }) }
        }
        switch result {
        case .success(let observation): image = observation; status = "Selected-file metadata read only. Docker ownership and VM capacity remain unverified."
        case .failure: image = nil; status = "File metadata unavailable or unsupported. Rechoose a regular local file; unknown size is not zero."
        }
    }
    func showExample() {
        guard !busy else { return }
        example = true; executable = nil; image = nil
        let lines = [
            "{\"Type\":\"Images\",\"TotalCount\":\"5\",\"Active\":\"2\",\"Size\":\"10GB\",\"Reclaimable\":\"2GB (20%)\"}",
            "{\"Type\":\"Local Volumes\",\"TotalCount\":\"2\",\"Active\":\"1\",\"Size\":\"12GB\",\"Reclaimable\":\"6GB (50%)\"}"
        ].joined(separator: "\n")
        inventory = try? DockerInventory.parseFixture(version: "fixture-only-1", output: lines)
        status = "Synthetic fixture only; no daemon, container or personal Docker installation was contacted."
    }
}

struct DockerInspectionView: View {
    @StateObject private var model = DockerInspection()
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.xl) {
            Button("Back to Overview", systemImage: "chevron.left", action: back)
            PageHeader(title: "Docker storage")
            Text("Read-only reporting and guidance").foregroundStyle(.secondary)
            Text("Supports the official Docker 28.5.1 static macOS CLI and Engine 28.5.1. Genuine runtime integration is not yet qualified. Daemon estimates do not establish host allocation or safe deletion.")
            SettingsRow(title: "Docker CLI", detail: "Choose the actual binary, not a shortcut. Unsupported releases are never executed.") {
                Button("Choose Docker CLI…") { model.chooseCLI() }
            }.disabled(model.busy)
            if let executable = model.executable { Text(executable.path).font(.caption).textSelection(.enabled) }
            SettingsRow(title: "Local daemon socket", detail: "Enter the absolute Unix socket path from your Docker configuration. No default context, remote connection or daemon startup.") {
                TextField("Local Unix socket path", text: $model.socketPath).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }.disabled(model.busy)
            Button(model.busy ? "Inspecting…" : "Inspect selected Docker") { Task { await model.inspectCLI() } }.disabled(model.executable == nil || model.socketPath.isEmpty || model.busy)
            StatusRow(text: model.status, symbol: "info.circle", identifier: "dockerInventoryStatus")
            SummarySurface {
            VStack(alignment: .leading, spacing: StillDesign.Space.sm) {
                Text("Host disk-image measurements").font(.headline)
                if let image = model.image { Text(image.url.path).font(.caption).textSelection(.enabled) }
                Text("Logical image-file length: \(bytes(model.image?.logicalBytes))")
                Text("Host allocated bytes: \(bytes(model.image?.allocatedBytes))")
                Text("VM virtual capacity: Unknown")
                Text("Logical length can differ from allocated bytes for sparse files. File length alone does not establish VM capacity. Docker ownership is unverified.").font(.caption).foregroundStyle(.secondary)
                Button("Choose disk image…") { Task { await model.chooseImage() } }.disabled(model.busy)
            }
            }
            if let inventory = model.inventory {
                Text(model.example ? "Synthetic daemon report" : "Daemon report").font(.headline)
                ForEach(inventory.categories, id: \.name) { category in
                    VStack(alignment: .leading, spacing: StillDesign.Space.xs) {
                        Text(category.persistentData ? "Local Volumes · Persistent application data" : category.name).font(.headline)
                        Text("\(category.total) total · \(category.active) active · Daemon-reported size: \(category.daemonSize ?? "Unknown")")
                        Text("Daemon estimate labelled reclaimable: \(category.daemonReclaimable ?? "Unknown") · No cleanup offered").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Persistent volumes may contain databases and application data. Use Docker Desktop to review storage ownership. Still never prunes, deletes, shrinks or moves Docker data.").foregroundStyle(.secondary)
            Divider()
            Button("Show synthetic Docker report") { model.showExample() }.disabled(model.busy)
        }
    }
    private func bytes(_ value: Int64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unknown"
    }
}
