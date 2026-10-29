import Testing
@testable import CacheDropCore

/// #352: clicking the active column flips its direction; clicking the other column switches to it, names A to Z and
/// sizes largest first.
@Test func clickingAColumnHeaderFlipsTheActiveOneOrSwitches() {
    var sort = ListSort()
    #expect(sort == ListSort(column: .size, ascending: false), "Size, largest first, by default")
    sort.select(.size)
    #expect(sort == ListSort(column: .size, ascending: true), "The active column flips")
    sort.select(.name)
    #expect(sort == ListSort(column: .name, ascending: true), "Another column starts A to Z")
    sort.select(.name)
    #expect(sort == ListSort(column: .name, ascending: false))
    sort.select(.size)
    #expect(sort == ListSort(column: .size, ascending: false), "Sizes start largest first")
}

private let sized: [(name: String, bytes: Int64)] = [("logic pro", 50), ("Zebra", 900), ("Ableton Live 12", 300), ("Ableton Live 2", 300), ("Éclair", 10)]
private func names(_ sort: ListSort) -> [String] { sort.ordered(sized, name: \.name, bytes: \.bytes).map(\.name) }

/// #352: either column sorts either way round; names as Finder sorts them, and rows of one size go by name A to Z.
@Test func aListSortsByNameOrSizeEitherWayRound() {
    #expect(names(ListSort(column: .name, ascending: true)) == ["Ableton Live 2", "Ableton Live 12", "Éclair", "logic pro", "Zebra"])
    #expect(names(ListSort(column: .name, ascending: false)) == ["Zebra", "logic pro", "Éclair", "Ableton Live 12", "Ableton Live 2"])
    #expect(names(ListSort()) == ["Zebra", "Ableton Live 2", "Ableton Live 12", "logic pro", "Éclair"])
    #expect(names(ListSort(column: .size, ascending: true)) == ["Éclair", "logic pro", "Ableton Live 2", "Ableton Live 12", "Zebra"])
}
