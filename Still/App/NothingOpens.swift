import StillCore

#if DEBUG
/// A debug test run opens nothing.
struct NothingOpens: GuidanceOpening {
    func open(_ target: GuidanceTarget) async -> Bool { true }
}
#endif
