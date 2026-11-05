import Foundation

/// How the Applications page orders and filters its Apps, Plug-ins and leftover groups (#295): one sort, set by the list's
/// sortable column header (#352), and one search for all three. Searching only hides rows; it never changes what is
/// ticked. Kept for the session, never across launches.
public struct ApplicationsListing: Sendable, Equatable {
    /// The sortable column header's choice (#352): Size, largest first, by default (Decision 51).
    public var sort: ListSort
    /// What the search field holds; blank matches every row.
    public var search: String
    public init(sort: ListSort = ListSort(), search: String = "") { self.sort = sort; self.search = search }

    /// Whether something is being searched for.
    public var isSearching: Bool { !query.isEmpty }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Whether a row of this name and maker is shown: either contains the search, ignoring case and accents.
    public func matches(name: String, maker: String?) -> Bool {
        let query = query
        return query.isEmpty || name.localizedStandardContains(query) || maker?.localizedStandardContains(query) == true
    }

    /// Whether a leftover is shown: by the removed app it is grouped under, its own name, or its maker.
    public func matches(_ leftover: Candidate) -> Bool {
        let name = leftover.itemName ?? leftover.url.lastPathComponent
        return matches(name: leftover.appName ?? name, maker: leftover.leftover?.owner.name) || matches(name: name, maker: nil)
    }

    /// The `items` the search matches, in this order.
    public func arranged<T>(_ items: [T], name: (T) -> String, maker: (T) -> String?, bytes: (T) -> Int64) -> [T] {
        sort.ordered(items.filter { matches(name: name($0), maker: maker($0)) }, name: name, bytes: bytes)
    }
}

/// What one Applications section shows (Decision 176).
public enum ApplicationsSectionContent: Sendable, Equatable {
    /// Nothing is listed yet and its list is being read: skeleton rows (#270).
    case loading
    /// Its list couldn't be read: its own line says why, with Scan again where it can help (Decision 62).
    case unreadable
    /// It found nothing: one row reading Empty, muted, in its size column, as Overview's empty categories (Decision 76).
    case empty
    /// It lists something, but nothing the search matches.
    case noMatches
    /// Its rows, behind its disclosure; during a rescan they stay, dimmed (#308).
    case rows
}

extension ApplicationsListing {
    /// What a section shows, from how many entries it lists and how many of those the search shows. A list that couldn't be
    /// read is said even while a scan runs, never as empty or a skeleton (Decision 62); Empty is true whatever the search.
    public func section(listed: Int, shown: Int, loading: Bool, unreadable: Bool = false) -> ApplicationsSectionContent {
        if listed > 0 { return shown > 0 ? .rows : .noMatches }
        if unreadable { return .unreadable }
        return loading ? .loading : .empty
    }

    /// What one of Audio software's four groups shows once the section lists something (Decision 176): Empty when it found
    /// nothing, as a section does; nil, left out, when a search has no match in it, an empty group included.
    public func group(listed: Int, shown: Int, unreadable: Bool = false) -> ApplicationsSectionContent? {
        if isSearching, shown == 0 { return nil }
        return section(listed: listed, shown: shown, loading: false, unreadable: unreadable)
    }
}
