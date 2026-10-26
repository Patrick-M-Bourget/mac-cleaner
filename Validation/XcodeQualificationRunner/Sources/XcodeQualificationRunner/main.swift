import Foundation
import Darwin
import StillCore

/// Native qualification only. It cannot inspect or mutate project files.
@main struct XcodeQualificationRunner {
    struct Observation: Encodable {
        let activity: String
        let reason: String?
        let source: String
        let runID: String
    }

    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true",
              environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              let run = environment["GITHUB_RUN_ID"], !run.isEmpty,
              let source = environment["GITHUB_SHA"], !source.isEmpty,
              CommandLine.arguments == [CommandLine.arguments[0], "owners"] else {
            fputs("Fresh GitHub-hosted owner qualification required.\n", stderr)
            exit(2)
        }
        let result = try NativeXcodeBuildEnvironment().ownerObservation()
        let record = Observation(activity: result.activity.rawValue, reason: result.reason,
                                 source: source, runID: run)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(record), as: UTF8.self))
    }
}
