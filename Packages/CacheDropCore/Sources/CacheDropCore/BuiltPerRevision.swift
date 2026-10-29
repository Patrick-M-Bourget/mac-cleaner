/// A value built once per revision of what it's built from, however often it is read (#362): Overview's summary is read on
/// every redraw. The owner moves the revision whenever an input changes; a read at the revision last built returns that value.
public struct BuiltPerRevision<Value> {
    private var built: (revision: UInt64, value: Value)?
    /// How many times it was built.
    public private(set) var builds = 0
    public init() {}
    public mutating func value(at revision: UInt64, build: () -> Value) -> Value {
        if let built, built.revision == revision { return built.value }
        let value = build()
        built = (revision, value); builds += 1
        return value
    }
}

extension BuiltPerRevision: Sendable where Value: Sendable {}
