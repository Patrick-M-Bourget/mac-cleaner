import Foundation

/// `tmutil listlocalsnapshots /`, which needs no admin rights. It names snapshots but gives no sizes.
public struct TmutilSnapshots: LocalSnapshotListing {
    public init() {}
    public func count() -> Int? {
        guard let output = try? BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/tmutil"), arguments: ["listlocalsnapshots", "/"], timeout: 10) else { return nil }
        return Self.count(in: output)
    }
    /// Lines naming a snapshot, such as `com.apple.TimeMachine.2026-10-26-101010.local`.
    public static func count(in output: String) -> Int {
        output.split(whereSeparator: \.isNewline).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("com.apple.TimeMachine.") }.count
    }
}
