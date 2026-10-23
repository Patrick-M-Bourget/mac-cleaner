import Foundation
import Testing
import StillCore

@Test func diagnosticsPreviewAllowlistRejectsPrivateVersionStrings() throws {
    let review = try DiagnosticsReview(appVersion: "/Users/private/person/Documents/secret.pdf", build: "person@example.com|123:456|ABCDEF12-3456-7890-ABCD-012345678901", system: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1), architecture: .arm64, scopeCount: 2, observedCount: 8, selectedCount: 1, scan: .partial, cleanup: .unknown, recovery: .requiresReview, errors: [.scanIncomplete, .outcomeUnknown])
    let object = try #require(JSONSerialization.jsonObject(with: review.payload) as? [String: Any])
    #expect(object["appVersion"] as? String == "Unknown")
    #expect(object["build"] as? String == "Unknown")
    #expect(object["scopeCount"] as? Int == 2)
    #expect(!review.text.contains("/Users"))
    #expect(!review.text.contains("person"))
    #expect(!review.text.contains("secret.pdf"))
    #expect(!review.text.contains("example.com"))
    #expect(!review.text.contains("123:456"))
    #expect(!review.text.contains("ABCDEF12-3456-7890-ABCD-012345678901"))
    #expect(Set(object.keys) == ["schema", "appVersion", "build", "systemVersion", "architecture", "scopeCount", "observedCount", "selectedCount", "scan", "cleanup", "recovery", "errors"])
}

@Test func diagnosticsSaveUsesExactlyReviewedBytesAndCancellationOrFailureKeepsReview() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillDiagnostics-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let review = try DiagnosticsReview(appVersion: "0.1", build: "2", system: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1), architecture: .arm64, scopeCount: 0, observedCount: 0, selectedCount: 0, scan: .notInspected, cleanup: .idle, recovery: .requiresReview, errors: [])
    var export = DiagnosticsExport(review: review)
    let unresolved = root.appendingPathComponent("unresolved.sqlite")
    try Data("protected recovery authority".utf8).write(to: unresolved)
    #expect(export.save(to: nil) == .cancelled)
    #expect(export.review.payload == review.payload)
    #expect(export.save(to: root.appendingPathComponent("missing-parent/report.json")) == .failed)
    #expect(export.review.payload == review.payload)
    let destination = root.appendingPathComponent("report.json")
    #expect(export.save(to: destination) == .saved)
    #expect(try Data(contentsOf: destination) == review.payload)
    #expect(export.review.text == review.text)
    #expect(try Data(contentsOf: unresolved) == Data("protected recovery authority".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["report.json", "unresolved.sqlite"])
}
