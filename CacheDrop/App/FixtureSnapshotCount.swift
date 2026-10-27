import Foundation
import CacheDropCore

#if DEBUG
/// A UI test's snapshot count, from `<home>/.cachedrop-test-snapshots`; none when it's missing.
struct FixtureSnapshotCount: LocalSnapshotListing {
    let home: URL?
    func count() -> Int? {
        guard let home, let text = try? String(contentsOf: home.appendingPathComponent(".cachedrop-test-snapshots"), encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
#endif
