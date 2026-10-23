import Foundation
import Darwin
import StillCore

private final class ProgressMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var first: Double?
    private var events = 0
    private var largestBatch = 0
    func observe(_ progress: ScanProgress) {
        lock.lock(); defer { lock.unlock() }
        if first == nil { first = progress.elapsed }
        events += 1; largestBatch = max(largestBatch, progress.recentObservations.count)
    }
    func report() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["firstUsefulProgressSeconds": first as Any? ?? NSNull(), "progressEvents": events, "largestBatch": largestBatch]
    }
}
private func memory() -> [String: Any] {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { return ["residentBytes": NSNull(), "processPeakResidentBytes": NSNull()] }
    return ["residentBytes": info.resident_size, "processPeakResidentBytes": info.resident_size_max]
}
private func write(_ report: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
}
@main struct ScanBenchmark {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, args[1] == "--entries", let entries = Int(args[2]), (1...1_000_000).contains(entries) else {
            print("Usage: ScanBenchmark --entries <1...1000000>; creates and removes only its owned temporary fixture")
            return
        }
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
        let capacity = try temporary.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        let available = Int64(capacity.volumeAvailableCapacity ?? 0)
        // Conservative fixture metadata reservation; never assume zero-byte files cost zero storage.
        let reservation = Int64(entries) * 16_384 + 1_073_741_824
        var report: [String: Any] = ["requestedFiles": entries, "hostOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory, "processorCount": ProcessInfo.processInfo.processorCount,
            "volumeCapacityBytes": capacity.volumeTotalCapacity as Any? ?? NSNull(), "availableBeforeBytes": available,
            "preflightReservationBytes": reservation, "reference512GBHost": false, "scannerRetainedEntryLimit": 100_000]
        guard available >= reservation else {
            report["fixtureCreated"] = false; report["status"] = "declined-insufficient-owned-fixture-headroom"
            try write(report); return
        }
        let root = temporary.appendingPathComponent("StillScanBenchmark-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let createdAt = ProcessInfo.processInfo.systemUptime
        for index in 0..<entries {
            if index % 1_000 == 0 {
                let headroom = try temporary.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
                guard headroom > 1_073_741_824 else { throw CocoaError(.fileWriteOutOfSpace) }
                try manager.createDirectory(at: root.appendingPathComponent("batch-\(index / 1_000)"), withIntermediateDirectories: false)
            }
            let path = root.appendingPathComponent("batch-\(index / 1_000)/file-\(index)").path
            let descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
            guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            close(descriptor)
        }
        report["fixtureCreated"] = true
        report["fixtureCreationSeconds"] = ProcessInfo.processInfo.systemUptime - createdAt
        report["memoryBeforeScan"] = memory()
        let progress = ProgressMetrics()
        let started = ProcessInfo.processInfo.systemUptime
        let result = try await FolderScanner().scan(root, onProgress: { progress.observe($0) })
        report["scanSeconds"] = ProcessInfo.processInfo.systemUptime - started
        report["observations"] = result.observations.count
        report["completeCoverage"] = result.isComplete
        report["issues"] = result.issues.map { $0.reason.rawValue }
        report["progress"] = progress.report()
        report["memoryAfterScan"] = memory()
        let cancellation = ScanCancellation()
        let cancelStarted = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await FolderScanner().scan(root, cancellation: cancellation, onProgress: { _ in cancellation.cancel() })
            report["cancellationStopped"] = false
        } catch is CancellationError {
            report["cancellationStopped"] = true
            report["cancelRequestToWorkerStopUpperBoundSeconds"] = ProcessInfo.processInfo.systemUptime - cancelStarted
        }
        report["status"] = "completed-owned-fixture-benchmark"
        report["fixtureCleanup"] = "owned root removed on process exit"
        try write(report)
    }
}
