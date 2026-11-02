import Foundation
import Testing
import CacheDropCore

/// Records every URL request made through the URL loading system while it is registered.
private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool {
        if let url = request.url { requests.append(url) }
        return false
    }
}

/// Licensing makes no network call (Decision 135, #594): activation, the check at launch and removal run with every URL
/// request recorded, and none is made. The source check below covers what this can't see.
@Test @MainActor func activatingCheckingAndRemovingALicenseMakesNoRequest() async throws {
    RecordingURLProtocol.requests = []
    URLProtocol.registerClass(RecordingURLProtocol.self)
    defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }
    let store = MemoryLicenseKeyStore()
    for verifier in [LicenseVerifier.production, LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [])] {
        let license = LicenseController(store: store, verifier: verifier)
        license.activate(LicenseTestKeyPair.vector)
        license.activate("CD1-NOTAKEY")
        _ = LicenseController(store: store, verifier: verifier).state.summary
        license.remove()
    }
    // The loading system asks protocols on its own queue, a moment after a task starts.
    try await Task.sleep(for: .milliseconds(500))
    #expect(RecordingURLProtocol.requests.isEmpty)
}

/// No licensing source can reach the network at all: none names a networking API. Covers CacheDropCore's `License*`
/// and `Trial*` files (#595) and the app's License section.
@Test func noLicensingSourceNamesANetworkingAPI() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardized
    let core = repo.appendingPathComponent("Packages/CacheDropCore/Sources/CacheDropCore")
    var files = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("License") || $0.lastPathComponent.hasPrefix("Trial") }
    files.append(repo.appendingPathComponent("CacheDrop/App/LicenseSettings.swift"))
    #expect(files.count >= 6)
    let network = try Regex("URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWPath|CFNetwork|CFStream|socket\\(|getaddrinfo|WKWebView")
    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(source.firstMatch(of: network) == nil, "\(file.lastPathComponent) names a networking API")
    }
}
