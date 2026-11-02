import Foundation
import CacheDropCore

// `cachedrop` (#626): read-only. `scan` prints Overview's categories, `plan` prints what Smart clean would clean, as text or
// with --json. It scans as the app does, with the user's Protected items, and never changes anything on disk.

let usage = """
Usage: cachedrop <command> [--json]

Commands:
  scan    What takes up space, by category, as Overview shows it
  plan    What Smart clean would clean now, item by item, and what the checks would skip

Read-only: nothing is changed. Clean up in CacheDrop to review and clean.
"""

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }
if arguments.contains("--help") || arguments.contains("-h") || arguments == ["help"] { print(usage); exit(0) }
guard arguments.count == 1, let command = arguments.first, command == "scan" || command == "plan" else { fail(usage, code: 64) }

let sources: SmartCleanReport.Sources
do { sources = try SmartCleanReport.Sources.currentUser() }
catch { fail("CacheDrop couldn’t read your Protected items, so it can’t check what’s safe to clean.", code: 1) }

do {
    if command == "scan" {
        let report = CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: sources.home, access: sources.access)
        print(json ? try CommandLineReport.json(report) : report.text)
    } else {
        let report = CommandLineReport.Plan(SmartCleanReport.run(sources))
        print(json ? try CommandLineReport.json(report) : report.text)
    }
} catch { fail("CacheDrop couldn’t write its report: \(error.localizedDescription)", code: 1) }
