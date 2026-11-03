import Foundation

/// One version's release notes (#553, Decision 161): the summary sentence, then the changes, read from the same
/// `docs/releases/<version>.html` content Sparkle shows (Decision 122), so Help → What’s New draws them natively.
public struct ReleaseNotes: Equatable, Sendable {
    public let version: String
    public let summary: String
    public let changes: [String]

    public init(version: String, summary: String, changes: [String]) {
        self.version = version; self.summary = summary; self.changes = changes
    }

    /// The most changes one version's notes list (Decision 122).
    static let maxChanges = 6
    /// The app bundles `docs/releases` as this folder of its resources; `scripts/check-release.sh` refuses a Release app
    /// without `<version>.html` in it.
    public static let bundledFolder = "releases"

    /// The running version's notes, from the app's resources (`Bundle.main.resourceURL`) and its marketing version
    /// (`CFBundleShortVersionString`).
    public static func bundled(version: String?, resources: URL?) throws -> ReleaseNotes {
        guard let version, let resources,
              let html = try? String(contentsOf: resources.appending(path: bundledFolder).appending(path: version + ".html"), encoding: .utf8)
        else { throw ReleaseNotesError.notBundled }
        return try ReleaseNotes(html: html, version: version)
    }

    /// Reads content in Decision 122's one shape, refusing what `scripts/release-notes.py` refuses: a `cd-card` with
    /// the eyebrow "What’s new in <version>", one plain summary and one to six plain changes, only `div`, `p`, `ul` and
    /// `li`, and no links, images, scripts or inline styles.
    public init(html: String, version: String) throws {
        let tags = Set(Self.texts(in: html, pattern: #"</?\s*([a-zA-Z0-9]+)"#).map { $0.lowercased() })
        let summaries = Self.texts(in: html, pattern: #"<p class="cd-summary">([^<]+)</p>"#)
        let changes = Self.texts(in: html, pattern: #"<li>([^<]+)</li>"#)
        guard tags.isSubset(of: ["div", "p", "ul", "li"]),
              html.range(of: #"\s(style|href|src|on[a-z]+)\s*="#, options: [.regularExpression, .caseInsensitive]) == nil,
              html.drop(while: \.isWhitespace).hasPrefix(#"<div class="cd-card">"#),
              html.contains(#"<p class="cd-eyebrow">What’s new in \#(version)</p>"#),
              summaries.count == 1, let summary = summaries.first,
              (1...Self.maxChanges).contains(changes.count), html.components(separatedBy: "<li").count - 1 == changes.count
        else { throw ReleaseNotesError.notInTheReleaseNotesShape }
        self.version = version
        self.summary = Self.decoded(summary)
        self.changes = changes.map(Self.decoded)
    }

    private static func texts(in html: String, pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    /// Plain text from the HTML: character references as their characters, and the source's line breaks as spaces.
    private static func decoded(_ text: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
        let regex = try! NSRegularExpression(pattern: #"&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);"#)
        var result = "", last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text) else { continue }
            let reference = String(text[name])
            let scalar: String? = if reference.hasPrefix("#x") || reference.hasPrefix("#X") {
                UInt32(reference.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
            } else if reference.hasPrefix("#") {
                UInt32(reference.dropFirst()).flatMap(Unicode.Scalar.init).map(String.init)
            } else { named[reference] }
            result += text[last..<whole.lowerBound] + (scalar ?? String(text[whole]))
            last = whole.upperBound
        }
        result += text[last...]
        return result.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

public enum ReleaseNotesError: Error, Equatable {
    /// This build has no notes for its version (a development build; a Release build fails `check-release.sh`).
    case notBundled
    /// The content isn't in Decision 122's shape for this version.
    case notInTheReleaseNotesShape
}
