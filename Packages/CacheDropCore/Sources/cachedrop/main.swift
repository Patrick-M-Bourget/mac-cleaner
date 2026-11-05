import Foundation
import Darwin
import CacheDropCore

// `cachedrop` (#626, #627). `scan` prints Overview's categories and `plan` what Smart clean would clean, read-only, as text
// or with --json. `clean` runs that plan through the app's own executor, checks and journal (`CommandLineClean`), after a
// confirmation unless --yes, asked only when the license and trial allow the run (#722); --dry-run runs the whole flow
// and changes nothing.

let usage = """
Usage: cachedrop <command> [--json]
       cachedrop clean [--dry-run] [--yes] [--json]

Commands:
  scan    What takes up space, by category, as Overview shows it
  plan    What Smart clean would clean now, item by item, and what the checks would skip
  clean   Clean what plan lists, checking each item again just before acting; History in CacheDrop shows the run

Options:
  --json     Print JSON for scripts and coding agents
  --dry-run  Run the whole cleanup and change nothing, saying what each item would do
  --yes      Clean without asking; needed when there’s no terminal to ask in

scan and plan are read-only: nothing is changed.
"""

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let flags: Set<String> = ["--json", "--dry-run", "--yes"]
let given = Array(CommandLine.arguments.dropFirst())
let json = given.contains("--json"), dryRun = given.contains("--dry-run"), yes = given.contains("--yes")
let arguments = given.filter { !flags.contains($0) }
if arguments.contains("--help") || arguments.contains("-h") || arguments == ["help"] { print(usage); exit(0) }
guard arguments.count == 1, let command = arguments.first, ["scan", "plan", "clean"].contains(command),
      command == "clean" || !(dryRun || yes) else { fail(usage, code: 64) }

// Refused before scanning: without --yes and a terminal to ask in, nothing would run anyway.
let start = CommandLineClean.start(yes: yes, dryRun: dryRun, interactive: isatty(STDIN_FILENO) == 1)
if command == "clean", start == .refuse { fail("cachedrop clean asks before cleaning. Run it in a terminal, or add --yes. Nothing was changed.", code: 1) }

let sources: SmartCleanReport.Sources
do { sources = try SmartCleanReport.Sources.currentUser() }
catch { fail("CacheDrop couldn’t read your Protected items, so it can’t check what’s safe to clean.", code: 1) }

do {
    switch command {
    case "scan":
        let report = CommandLineReport.Scan(catalog: sources.catalog, discovery: SmartCleanReport.discover(sources), home: sources.home, access: sources.access)
        print(json ? try CommandLineReport.json(report) : report.text)
    case "plan":
        let report = CommandLineReport.Plan(SmartCleanReport.run(sources))
        print(json ? try CommandLineReport.json(report) : report.text)
    default:
        let report = SmartCleanReport.run(sources), plan = CommandLineReport.Plan(report)
        guard !report.picked.isEmpty else {
            // With --json, scripts still get a report: an empty one.
            if json { print(try CommandLineReport.json(CommandLineReport.Clean(nothingToCleanIn: sources.home, dryRun: dryRun))) }
            fail("Smart clean has nothing to clean now. Nothing was changed.", code: 0)
        }
        // The app's license and trial (Decisions 135, 138): gated in builds with LICENSE_GATING, as the Release app is.
        // Without it, as in Debug, nothing reads or writes the Keychain. Either way the stores only update the app's items.
        #if LICENSE_GATING
        let gating = true
        #else
        let gating = false
        #endif
        let licenseStore = KeychainLicenseKeyStore(createsItem: false), trialStore = KeychainTrialStore(createsItem: false)
        if start == .ask {
            // Asked only when the license and trial would let the run go ahead (#722); `run` checks them again.
            if let reason = CommandLineClean.refusalBeforeAsking(report, sources: sources, dryRun: dryRun, licenseStore: licenseStore,
                                                                 trialStore: trialStore, gating: gating) { fail(reason, code: 1) }
            // The question and the plan go to standard error, so --json output stays only JSON.
            FileHandle.standardError.write(Data((plan.text.components(separatedBy: "\n").dropLast().joined(separator: "\n")
                                                + "\nClean up \(plan.total.text) now? [y/N] ").utf8))
            guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), ["y", "yes"].contains(answer) else {
                fail("Nothing was changed.", code: 1)
            }
        }
        let journal: SQLiteCleanupJournal, lock: URL
        do { journal = try LocalStateLocation.cleanupJournal(); lock = try LocalStateLocation.root(create: true).appendingPathComponent(LocalStateLocation.cleanupLockName) }
        catch { fail(CommandLineClean.Refusal.journal, code: 1) }
        switch await CommandLineClean.run(report, sources: sources, dryRun: dryRun, journal: journal, lock: lock, trash: FinderTrash(),
                                          licenseStore: licenseStore, trialStore: trialStore, gating: gating) {
        case .refused(let reason): fail(reason, code: 1)
        case .ran(let result, let notice):
            let shown = CommandLineReport.Clean(result, home: sources.home)
            print(json ? try CommandLineReport.json(shown) : shown.text)
            if let notice { FileHandle.standardError.write(Data((notice + "\n").utf8)) }
            if let failure = result.journalFailure { fail(failure, code: 1) }
        }
    }
} catch { fail("CacheDrop couldn’t write its report: \(error.localizedDescription)", code: 1) }
