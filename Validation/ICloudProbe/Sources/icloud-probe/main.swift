import Foundation
import CloudProbe

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard arguments.count == 2, arguments[0] == "--inspect-disposable" else {
        throw NSError(domain: "CloudProbe", code: 64, userInfo: [NSLocalizedDescriptionKey: "Usage: icloud-probe --inspect-disposable /explicit/path/StillCloudProbe-<id>/disposable.txt (metadata only; eviction unsupported)"])
    }
    let report = try CloudProbe.inspectDisposable(URL(fileURLWithPath: arguments[1]))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
} catch {
    // Error descriptions may contain paths. This harness prints no path or account identifiers.
    FileHandle.standardError.write(Data("Probe refused or metadata unavailable (\((error as NSError).domain):\((error as NSError).code)). No eviction attempted.\n".utf8))
    exit(1)
}
