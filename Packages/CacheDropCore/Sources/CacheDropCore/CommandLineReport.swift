import Foundation

/// What `cachedrop scan` and `cachedrop plan` print (#626): Overview's categories and Smart clean's plan, built from the
/// same types the app draws them from (`CatalogOverview`, `RecommendedPlan` through `SmartCleanReport`) and worded the
/// same way. Read-only: it holds what a scan found, never anything that acts. The JSON keys are a contract for scripts and
/// coding agents, so each is pinned.
public enum CommandLineReport {
    /// A size as the app says it, with its bytes for scripts: nil when unknown; a lower bound for `atLeast`.
    public struct Size: Encodable, Equatable, Sendable {
        public let text: String
        public let bytes: Int64?
        /// "measured", "atLeast", "about" or "unknown" (SPEC section 6).
        public let kind: String
        private enum CodingKeys: String, CodingKey { case text = "text", bytes = "bytes", kind = "kind" }
        init(_ estimate: SizeEstimate, text: String) {
            self.text = text
            switch estimate {
            case .measured(let value): bytes = value; kind = "measured"
            case .atLeast(let value): bytes = value; kind = "atLeast"
            case .about(let value): bytes = value; kind = "about"
            case .unknown: bytes = nil; kind = "unknown"
            }
        }
        init(_ items: [Candidate], catalog: Catalog) {
            let estimate = SizeEstimate(sum: items.map(SizeEstimate.init))
            self.init(estimate, text: estimate.text(upperBound: items.contains { catalog.rule($0.ruleID)?.estimateIsUpperBound == true }))
        }
    }

    /// `cachedrop scan`: Overview's categories, in Overview's order (`visibleRows`).
    public struct Scan: Encodable, Sendable {
        public struct Category: Encodable, Sendable {
            public let id: String
            public let title: String
            /// "found", "empty" or "needsFullDiskAccess" (Decision 62: never "Empty" when it couldn't be read).
            public let status: String
            public let size: Size?
            public let items: Int
            private enum CodingKeys: String, CodingKey { case id = "id", title = "title", status = "status", size = "size", items = "items" }
        }
        public let home: String
        public let scannedAt: Date
        /// "granted", "notGranted" or "unknown".
        public let fullDiskAccess: String
        /// Overview's "Recommended for review": cleanable space, not counting what would go to the Trash.
        public let recommended: Size
        public let toTrash: Size
        public let categories: [Category]
        private enum CodingKeys: String, CodingKey {
            case home = "home", scannedAt = "scannedAt", fullDiskAccess = "fullDiskAccess", recommended = "recommended", toTrash = "toTrash", categories = "categories"
        }

        public init(catalog: Catalog, discovery: CatalogDiscovery, home: URL, access: FullDiskAccessStatus, now: Date = Date()) {
            let overview = CatalogOverview(catalog: catalog, candidates: discovery.candidates, notAccessible: discovery.notAccessible)
            self.home = home.standardizedFileURL.path; scannedAt = now
            fullDiskAccess = switch access { case .granted: "granted"; case .notGranted: "notGranted"; case .unknown: "unknown" }
            recommended = Size(overview.recommended, text: CatalogOverview.recommendedText(overview.recommended))
            toTrash = Size(overview.proposedForTrash, text: SizeFormatter.text(overview.proposedForTrash))
            categories = overview.visibleRows.map { row in
                let status = !row.isEmpty ? "found" : row.needsAccess ? "needsFullDiskAccess" : "empty"
                return Category(id: row.category.rawValue, title: row.category.overviewTitle, status: status,
                                size: row.isEmpty ? nil : Size(row.estimate, text: row.valueText), items: row.itemCount)
            }
        }

        public var text: String {
            var lines = ["CacheDrop scan of \(home)", "Recommended for review: \(recommended.text)"]
            if toTrash.bytes.map({ $0 > 0 }) == true { lines.append("Doesn’t include \(toTrash.text) that would go to the Trash") }
            lines.append("")
            let width = categories.map(\.title.count).max() ?? 0
            for category in categories {
                let value = category.size?.text ?? (category.status == "needsFullDiskAccess" ? "Needs Full Disk Access" : "Empty")
                lines.append(category.title.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
            }
            lines += ["", "Read-only · Nothing was changed"]
            return lines.joined(separator: "\n")
        }
    }

    /// `cachedrop plan`: what Smart clean would clean now, by category, with what the checks would skip.
    public struct Plan: Encodable, Sendable {
        public struct Item: Encodable, Sendable {
            public let path: String
            public let size: Size
            /// The rule's action: "delete", "moveToTrash", "tool" or "evict".
            public let action: String
            public let reason: String
            private enum CodingKeys: String, CodingKey { case path = "path", size = "size", action = "action", reason = "reason" }
        }
        public struct Category: Encodable, Sendable {
            public let id: String
            public let title: String
            public let size: Size
            /// Smart clean's one consequence line for the category.
            public let consequence: String
            public let items: [Item]
            private enum CodingKeys: String, CodingKey { case id = "id", title = "title", size = "size", consequence = "consequence", items = "items" }
        }
        public struct Skipped: Encodable, Sendable {
            public let path: String
            public let size: Size
            public let reason: String
            private enum CodingKeys: String, CodingKey { case path = "path", size = "size", reason = "reason" }
        }
        public let home: String
        public let scannedAt: Date
        public let total: Size
        public let toTrash: Size
        public let categories: [Category]
        public let skipped: [Skipped]
        private enum CodingKeys: String, CodingKey {
            case home = "home", scannedAt = "scannedAt", total = "total", toTrash = "toTrash", categories = "categories", skipped = "skipped"
        }

        public init(_ report: SmartCleanReport) {
            let catalog = report.catalog
            let all = report.picked.map(\.candidate)
            home = report.home.standardizedFileURL.path; scannedAt = report.date
            total = Size(all, catalog: catalog)
            toTrash = Size(all.filter { $0.action == .trash }, catalog: catalog)
            func item(_ entry: SmartCleanReport.Item) -> Item {
                Item(path: entry.candidate.url.path, size: Size([entry.candidate], catalog: catalog), action: entry.candidate.action.rawValue, reason: entry.reason)
            }
            var order: [CatalogCategory] = []
            for rule in catalog.rules where !order.contains(rule.category) && all.contains(where: { $0.ruleID == rule.id }) { order.append(rule.category) }
            categories = order.map { category in
                let entries = report.picked.filter { catalog.rule($0.candidate.ruleID)?.category == category }
                let rules = catalog.rules.filter { rule in rule.category == category && entries.contains { $0.candidate.ruleID == rule.id } }
                return Category(id: category.rawValue, title: category.smartCleanTitle, size: Size(entries.map(\.candidate), catalog: catalog),
                                consequence: SmartCleanConsequence.line(for: category, rules: rules),
                                items: entries.sorted { $0.candidate.estimatedBytes > $1.candidate.estimatedBytes }.map(item))
            }
            skipped = report.skipped.map { Skipped(path: $0.candidate.url.path, size: Size([$0.candidate], catalog: catalog), reason: $0.refusal.reason) }
        }

        public var text: String {
            func path(_ value: String) -> String { value.hasPrefix(home + "/") ? "~" + value.dropFirst(home.count) : value }
            let count = categories.reduce(0) { $0 + $1.items.count }
            var lines = ["Smart clean would clean \(count) \(count == 1 ? "item" : "items"), \(total.text)"]
            if toTrash.bytes.map({ $0 > 0 }) == true { lines.append(SmartCleanConsequence.goesToTrash(toTrash.text)) }
            for category in categories {
                lines += ["", "\(category.title) · \(category.size.text) · \(category.consequence)"]
                for item in category.items { lines.append("  \(item.size.text)  \(path(item.path))  — \(item.reason)") }
            }
            if !skipped.isEmpty {
                lines += ["", "Skipped by the checks (\(skipped.count))"]
                for item in skipped { lines.append("  \(item.size.text)  \(path(item.path))  — \(item.reason)") }
            }
            lines += ["", "Read-only · Nothing was changed. Clean up in CacheDrop to review and clean these."]
            return lines.joined(separator: "\n")
        }
    }

    /// `cachedrop clean` (#627): what the run did, as Results says it. A dry run says what would be affected and frees
    /// nothing; otherwise the measured freed space leads (SPEC section 6), unless the run only moved items to the Trash.
    public struct Clean: Encodable, Sendable {
        public struct Item: Encodable, Sendable {
            public let path: String
            /// The rule's action: "delete", "moveToTrash", "tool" or "evict".
            public let action: String
            /// The journal's state: "succeeded", "skipped", "failed", "cancelled" or "unknown".
            public let state: String
            /// History's line for the item: its outcome, then its message when that adds something.
            public let outcome: String
            private enum CodingKeys: String, CodingKey { case path = "path", action = "action", state = "state", outcome = "outcome" }
        }
        public let home: String
        public let dryRun: Bool
        /// Nil in a dry run and when the run only moved items to the Trash; "Unknown" when a reading is missing.
        public let measuredFreed: Size?
        public let toTrash: Size
        /// A dry run's size: what the run would have affected. Nil, and left out, for a run that changed things.
        public let wouldBeAffected: Size?
        public let items: [Item]
        private enum CodingKeys: String, CodingKey {
            case home = "home", dryRun = "dryRun", measuredFreed = "measuredFreed", toTrash = "toTrash", wouldBeAffected = "wouldBeAffected", items = "items"
        }

        /// The report when Smart clean has nothing to clean: no run, nothing changed.
        public init(nothingToCleanIn home: URL, dryRun: Bool) {
            self.home = home.standardizedFileURL.path; self.dryRun = dryRun; measuredFreed = nil
            toTrash = Size(.measured(0), text: SizeFormatter.text(Int64(0))); items = []; affected = 0
            wouldBeAffected = dryRun ? toTrash : nil
        }

        public init(_ result: CatalogExecutionResult, home: URL) {
            self.home = home.standardizedFileURL.path; dryRun = result.dryRun
            if result.dryRun || result.records.movedOnlyToTrash { measuredFreed = nil }
            else {
                let shown = MeasuredFreedSpace.shown(result.measuredFreedBytes)
                let estimate: SizeEstimate = shown.map(SizeEstimate.measured) ?? .unknown
                measuredFreed = Size(estimate, text: SizeFormatter.text(estimate))
            }
            toTrash = Size(.measured(result.movedToTrashBytes), text: SizeFormatter.text(result.movedToTrashBytes))
            items = result.records.attentionFirst.map {
                Item(path: $0.originalURL.path, action: $0.action, state: $0.state.rawValue, outcome: $0.outcomeLine)
            }
            affected = result.records.filter(\.wasDryRun).reduce(0) { $0 + $1.recordedBytes }
            wouldBeAffected = result.dryRun ? Size(.measured(affected), text: SizeFormatter.text(affected)) : nil
        }
        private let affected: Int64

        public var text: String {
            func path(_ value: String) -> String { value.hasPrefix(home + "/") ? "~" + value.dropFirst(home.count) : value }
            var lines: [String] = []
            if dryRun { lines.append("Dry run · Nothing changed · " + SizeFormatter.text(affected) + " would be affected") }
            if let measuredFreed { lines.append("Measured freed space: " + measuredFreed.text) }
            if toTrash.bytes.map({ $0 > 0 }) == true { lines.append("In the Trash · Freed when you empty it: " + toTrash.text) }
            if items.isEmpty { lines.append("Nothing to clean") }
            lines.append("")
            for item in items { lines.append("  \(path(item.path))  — \(item.outcome)") }
            return lines.joined(separator: "\n")
        }
    }

    /// JSON for scripts and agents: pretty, sorted keys, ISO 8601 dates.
    public static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
