import Foundation
import StillCore

#if DEBUG
/// iCloud states for a UI test's fixture home: `.still-test-icloud.json` maps paths relative to the home to
/// "ready", "pinned", "notUploaded" or "conflicted". Evicting only records the path in `.still-test-icloud-evicted`.
struct FixtureUbiquitousItems: UbiquitousItemAccess {
    let home: URL?
    func metadata(_ url: URL) -> CloudMetadata {
        guard let home, let data = try? Data(contentsOf: home.appendingPathComponent(".still-test-icloud.json")),
              let states = try? JSONDecoder().decode([String: String].self, from: data),
              url.path.hasPrefix(home.path + "/"), let state = states[String(url.path.dropFirst(home.path.count + 1))] else { return .unknown }
        return CloudMetadata(membership: true, downloadState: .current, uploaded: state != "notUploaded", uploading: false, downloading: false,
                             conflicts: state == "conflicted", pinned: state == "pinned")
    }
    func evict(_ url: URL) throws {
        guard let home else { throw CocoaError(.fileWriteNoPermission) }
        let log = home.appendingPathComponent(".still-test-icloud-evicted")
        let previous = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try (previous + url.path + "\n").write(to: log, atomically: true, encoding: .utf8)
    }
}
#endif
