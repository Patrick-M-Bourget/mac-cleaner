import Foundation
import Testing
@testable import CacheDropCore

/// #553, Decision 161: Help → What’s New reads the running version's notes, the same content Sparkle shows (Decision 122).
@Suite struct ReleaseNotesTests {
    private let notes = """
    <div class="cd-card">
    <p class="cd-eyebrow">What’s new in 1.0.1</p>
    <p class="cd-summary">Empty the Trash from CacheDrop, and run CacheDrop on more Macs.</p>
    <ul class="cd-changes">
    <li>Empty Trash… lists everything in the Trash before it deletes it.</li>
    <li>CacheDrop now runs on macOS 14 Sonoma and later, on Intel Macs too.</li>
    </ul>
    </div>

    """

    @Test func readsTheSummaryThenTheChangesInOrder() throws {
        let parsed = try ReleaseNotes(html: notes, version: "1.0.1")
        #expect(parsed.version == "1.0.1")
        #expect(parsed.summary == "Empty the Trash from CacheDrop, and run CacheDrop on more Macs.")
        #expect(parsed.changes == ["Empty Trash… lists everything in the Trash before it deletes it.",
                                   "CacheDrop now runs on macOS 14 Sonoma and later, on Intel Macs too."])
    }

    /// Another version's notes never show as this version's.
    @Test func notesWhoseEyebrowNamesAnotherVersionAreRefused() {
        #expect(throws: ReleaseNotesError.notInTheReleaseNotesShape) { try ReleaseNotes(html: notes, version: "1.0.2") }
    }

    /// The same refusals as scripts/release-notes.py: anything it wouldn't sign isn't drawn either.
    @Test func contentOutsideTheOneShapeIsRefused() {
        let outside = [
            "",
            notes.replacingOccurrences(of: "<div class=\"cd-card\">", with: "<div>"),
            notes.replacingOccurrences(of: "<li>Empty", with: "<li><a href=\"x\">Empty</a>"),
            notes.replacingOccurrences(of: "<li>Empty", with: "<li style=\"color:red\">Empty"),
            notes.replacingOccurrences(of: "</ul>", with: "</ul><img>"),
            notes.replacingOccurrences(of: "<p class=\"cd-summary\">Empty", with: "<p class=\"cd-summary\"><b>Empty</b>"),
            notes.replacingOccurrences(of: "</ul>", with: "</ul><p class=\"cd-summary\">Twice.</p>"),
            notes.replacingOccurrences(of: #"<li>[^\n]*\n"#, with: "", options: .regularExpression),
            notes.replacingOccurrences(of: "<ul class=\"cd-changes\">", with: "<ul class=\"cd-changes\">" + String(repeating: "<li>More.</li>", count: 5)),
        ]
        for html in outside {
            #expect(throws: ReleaseNotesError.notInTheReleaseNotesShape, "\(html)") { try ReleaseNotes(html: html, version: "1.0.1") }
        }
    }

    @Test func sixChangesIsTheMost() throws {
        let six = notes.replacingOccurrences(of: "<ul class=\"cd-changes\">", with: "<ul class=\"cd-changes\">" + String(repeating: "<li>More.</li>\n", count: 4))
        #expect(try ReleaseNotes(html: six, version: "1.0.1").changes.count == 6)
    }

    @Test func characterReferencesReadAsTheirCharacters() throws {
        let escaped = notes.replacingOccurrences(of: "Empty Trash…", with: "Q&amp;A &lt;new&gt; &quot;Trash&quot; &#8217;s &#x2014;")
        #expect(try ReleaseNotes(html: escaped, version: "1.0.1").changes.first == "Q&A <new> \"Trash\" ’s — lists everything in the Trash before it deletes it.")
    }

    /// Every version's notes since Decision 122 read, so a release never bundles notes the window can't show. 0.9.3's
    /// came before that shape, and no build of 0.9.3 has the window.
    @Test func everyShippedVersionsNotesRead() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../docs/releases").standardized
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" && $0.lastPathComponent != "0.9.3.html" }
        #expect(!files.isEmpty)
        for file in files {
            let version = file.deletingPathExtension().lastPathComponent
            let parsed = try ReleaseNotes(html: String(contentsOf: file, encoding: .utf8), version: version)
            #expect(!parsed.changes.isEmpty, "\(version)")
        }
    }

    /// The app reads the running version's file from the folder the build bundles (`Resources/releases`).
    @Test func theRunningVersionsNotesAreReadFromTheBundledFolder() throws {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent("CacheDropReleaseNotes-\(UUID())")
        defer { try? FileManager.default.removeItem(at: resources) }
        let folder = resources.appending(path: ReleaseNotes.bundledFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try notes.write(to: folder.appending(path: "1.0.1.html"), atomically: true, encoding: .utf8)
        try notes.replacingOccurrences(of: "1.0.1", with: "1.0.0").write(to: folder.appending(path: "1.0.0.html"), atomically: true, encoding: .utf8)
        #expect(try ReleaseNotes.bundled(version: "1.0.1", resources: resources).version == "1.0.1")
        #expect(throws: ReleaseNotesError.notBundled) { try ReleaseNotes.bundled(version: "1.0.2", resources: resources) }
        #expect(throws: ReleaseNotesError.notBundled) { try ReleaseNotes.bundled(version: "1.0.1", resources: nil) }
        #expect(throws: ReleaseNotesError.notBundled, "No version in the bundle") { try ReleaseNotes.bundled(version: nil, resources: resources) }
    }
}
