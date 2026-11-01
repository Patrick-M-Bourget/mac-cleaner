import Foundation

/// The rescan after a run reads again only the rules the run acted on (Decision 133, #556 part 2).
extension CatalogExecutionResult {
    /// Every rule an item of the run belongs to, whether it was cleaned or refused, so its rows come back as they now are.
    public var ruleIDs: Set<String> { Set(records.compactMap(\.ruleID)) }
    /// The `folders` (remembered folders) the run may have changed: one holding an item it acted on, or inside one, symbolic
    /// links resolved. A dry run changed nothing.
    public func foldersTouched(among folders: [URL]) -> [URL] {
        let acted = actedPaths
        return folders.filter { folder in Self.overlaps(folder.resolvingSymlinksInPath().standardizedFileURL.path, acted) }
    }
    /// The paths of the items the run may have changed, symbolic links resolved: none for a dry run.
    var actedPaths: [String] {
        guard !dryRun else { return [] }
        return records.filter { $0.state != .skipped && $0.state != .pending }.map { $0.originalURL.resolvingSymlinksInPath().standardizedFileURL.path }
    }
    /// Whether `path` is one of `paths`, inside one, or holds one.
    static func overlaps(_ path: String, _ paths: [String]) -> Bool {
        paths.contains { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }
    }
}

extension Catalog {
    /// The rules the rescan after `run` reads again: those of its items, cleaned or refused; any rule with a `shown` row at,
    /// inside or holding what it acted on, so a cleaned item never shows as still there (Decision 80); and the rules that share
    /// one reading with any of them (Docker's `docker system df`, simctl's lists), so a shared reading and its note stay one.
    public func rescanned(after run: CatalogExecutionResult, shown: [Candidate]) -> Set<String> {
        let acted = run.actedPaths
        let nested = shown.filter { CatalogExecutionResult.overlaps($0.url.resolvingSymlinksInPath().standardizedFileURL.path, acted) }.map(\.ruleID)
        return rescanned(ruleIDs: run.ruleIDs.union(nested))
    }
    func rescanned(ruleIDs: Set<String>) -> Set<String> {
        func reading(_ rule: CleanupRule) -> String? {
            switch rule.items {
            case .docker: "docker"
            case .simulatorRuntimes, .simulatorDevices, .unavailableSimulators: "simulators"
            default: nil
            }
        }
        let shared = Set(rules.filter { ruleIDs.contains($0.id) }.compactMap(reading))
        return ruleIDs.union(rules.filter { reading($0).map(shared.contains) ?? false }.map(\.id))
    }

    /// What a full scan would show, from what is `shown` and a `discovery(only: rescanned)`: the rescanned rules' rows, notes
    /// and Full Disk Access rows replaced, every other rule's kept as they were. Rows stay in catalog order, each space offered
    /// once to the first rule that has it (as discovery does). Files from deleted apps that a rescanned rule now offers leave,
    /// the way a full scan leaves them to that rule; the rest stay, after the rules.
    public func merging(_ fresh: CatalogDiscovery, rescanned: Set<String>, into shown: CatalogDiscovery) -> CatalogDiscovery {
        let order = Dictionary(rules.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func isLeftover(_ candidate: Candidate) -> Bool { AppRuleFamily.of(ruleID: candidate.ruleID) == .removedAppLeftovers }
        let kept = shown.candidates.filter { !isLeftover($0) && !rescanned.contains($0.ruleID) }
        let ordered = (kept + fresh.candidates).enumerated()
            .sorted { (order[$0.element.ruleID] ?? .max, $0.offset) < (order[$1.element.ruleID] ?? .max, $1.offset) }.map(\.element)
        var seen = Set<String>()
        let offered = ordered.filter { seen.insert(spaceKey(of: $0)).inserted }
        return CatalogDiscovery(candidates: offered + RemovedAppLeftovers.notOffered(by: offered, shown.candidates.filter(isLeftover)),
                                notes: shown.notes.filter { !rescanned.contains($0.ruleID) } + fresh.notes,
                                notAccessible: shown.notAccessible.filter { !rescanned.contains($0.id) } + fresh.notAccessible)
    }
}
