/// Background work the bottom bar reports as one quiet line (Decision 46): the work that started first, plus how many more
/// are running ("Checking npm cache… 4 of 31 · +1 more"). Each piece of work is named by an id; its text is read live.
public struct BackgroundWork: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// The id of the work the line names.
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
    }
    /// Running work, earliest first.
    public private(set) var running: [String] = []
    public init() {}
    /// Records what runs now: finished work leaves, new work goes after the work already running.
    public mutating func update(running now: Set<String>) {
        running.removeAll { !now.contains($0) }
        running += now.subtracting(running).sorted()
    }
    /// The bar's line, given each running work's own text; nil when nothing runs.
    public func line(_ text: (String) -> String) -> Line? {
        guard let first = running.first else { return nil }
        let others = running.count - 1
        return Line(id: first, text: others > 0 ? text(first) + " · +\(others) more" : text(first))
    }
}
