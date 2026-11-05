import Foundation

/// Smart clean's **Worth a look** (#780, Decision 178): the files from deleted apps `RecommendedPlan` doesn't take (possibly
/// related ones, or any tie it doesn't recommend), listed unticked under Smart clean's ticked categories. The ones it takes
/// stay ticked in Files from deleted apps' own row, so nothing is shown twice. Ticks are shared with Applications (one
/// selection, Decision 67); possibly related items are ticked one by one (Decision 49). What's in it counts in Smart clean's
/// Free up X and Clean up only once ticked. It also holds **Apps you haven’t opened in 6 months** (#781, Decision 188).
public enum WorthALook {
    public static let title = "Worth a look"
    /// The rules whose items it may hold: told apart by rule ID, so a choice reads the same with no catalog at hand.
    static let ruleIDs: Set<String> = Set(RemovedAppLeftovers.rules.map(\.id))

    /// The items among `found` it holds: files from deleted apps the recommended `plan` neither takes nor holds.
    public static func candidates(in found: [Candidate], plan: RecommendedPlan) -> [Candidate] {
        let planned = Set((plan.candidates + plan.held).map(\.id))
        return found.filter { offers(id: $0.id, notIn: planned) }
    }
    /// The same rule from ids alone: a file from a deleted app that isn't among the plan's `planned` ids.
    static func offers(id: String, notIn planned: Set<String>) -> Bool {
        !planned.contains(id) && ruleIDs.contains(String(id.prefix { $0 != "|" }))
    }

    /// Its rows, one per category its `candidates` fill; none means no group and no header.
    public static func rows(_ candidates: [Candidate], catalog: Catalog) -> [CatalogOverview.Row] {
        CatalogOverview(catalog: catalog, candidates: candidates).rows.filter { $0.itemCount > 0 }
    }

    // MARK: Apps you haven't opened in 6 months (#781, Decision 188)

    public static let appsTitle = "Apps you haven’t opened in 6 months"
    /// An app is suggested once Spotlight says it hasn't been opened in this many days.
    public static let unopenedDays = 180

    /// The apps it suggests, one app bundle each: apps CacheDrop can uninstall (`AppUninstall`, never a plug-in product or an
    /// app's own uninstaller), last opened `unopenedDays` or more before `now`. An unknown last-opened date is never taken as
    /// old, so such an app isn't suggested; nor is Apple's own, nor one something holds: in use at the scan, or refused by
    /// `check` now (its owner running, #374).
    public static func unopenedApps(in uninstallable: [Candidate], now: Date, check: (Candidate) -> CheckRefusal?) -> [Candidate] {
        let cutoff = now.addingTimeInterval(-TimeInterval(unopenedDays) * .secondsPerDay)
        return uninstallable.filter { item in
            guard item.ruleID == AppUninstall.appRuleID, let app = item.uninstall, app.plugIn == nil,
                  item.url.standardizedFileURL.path == URL(fileURLWithPath: app.path).standardizedFileURL.path,
                  !app.bundleID.lowercased().hasPrefix("com.apple."), let opened = app.lastOpened, opened <= cutoff else { return false }
            return item.hold == nil && check(item) == nil
        }
    }

    /// Everything uninstalled with the suggested `apps` among `uninstallable`: what Smart clean takes once ticked, as
    /// Applications would (the app, its own uninstaller and its allow-listed files, Decision 57).
    public static func items(of apps: [Candidate], in uninstallable: [Candidate]) -> [Candidate] {
        let paths = Set(apps.compactMap(\.uninstall?.path))
        return uninstallable.filter { item in item.uninstall.map { paths.contains($0.path) } ?? false }
    }

    /// An app row's line: "Last opened March 2026".
    public static func lastOpenedText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "MMMM yyyy"
        return "Last opened " + format.string(from: date)
    }
}
