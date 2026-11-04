import Foundation
import Testing
import CacheDropCore

/// Stands in for the Keychain: Core tests never touch the real one.
@MainActor final class MemoryLicenseKeyStore: LicenseKeyStore {
    var key: String?
    var failReads = false, failWrites = false, failRemoves = false
    init(_ key: String? = nil) { self.key = key }
    func read() throws -> String? { if failReads { throw CocoaError(.fileReadNoPermission) }; return key }
    func write(_ value: String) throws { if failWrites { throw CocoaError(.fileWriteNoPermission) }; key = value }
    func remove() throws { if failRemoves { throw CocoaError(.fileWriteNoPermission) }; key = nil }
}

private let verifier = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [])

@Test @MainActor func aPastedKeyIsCheckedKeptAndReadAgainAtTheNextLaunch() {
    let store = MemoryLicenseKeyStore()
    let license = LicenseController(store: store, verifier: verifier)
    #expect(license.state == .none)
    let pasted = "  " + LicenseTestKeyPair.vector.lowercased() + "\n"
    #expect(license.activate(pasted))
    guard case .active = license.state else { Issue.record("not active"); return }
    #expect(store.key == LicenseTestKeyPair.vector, "The Keychain keeps the canonical key")
    #expect(LicenseController(store: store, verifier: verifier).state == license.state)
}

/// A pasted key that isn't valid, or is revoked, is never kept: the license on this Mac stays as it was, and `rejected`
/// says why until the next paste or removal.
@Test @MainActor func aRejectedKeyIsNotKeptAndSaysWhy() {
    let store = MemoryLicenseKeyStore(LicenseTestKeyPair.vector)
    let revoking = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [LicenseTestKeyPair.vectorID])
    let empty = MemoryLicenseKeyStore()
    let license = LicenseController(store: empty, verifier: revoking)
    #expect(!license.activate(LicenseTestKeyPair.vector))
    guard case .revoked = license.rejected else { Issue.record("not revoked"); return }
    #expect(license.state == .none && empty.key == nil)

    let active = LicenseController(store: store, verifier: verifier)
    let before = active.state
    #expect(!active.activate("CD1-NOTAKEY"))
    #expect(active.rejected == .invalid)
    #expect(active.state == before && store.key == LicenseTestKeyPair.vector)
    #expect(active.activate(LicenseTestKeyPair.vector))
    #expect(active.rejected == nil)
}

/// A kept key reads as what it is at launch: revoked once a release lists it, invalid if it no longer checks out. Remove
/// from this Mac forgets it whatever it is.
@Test @MainActor func aKeptKeyIsCheckedAtLaunchAndRemoveForgetsIt() {
    let revoking = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [LicenseTestKeyPair.vectorID])
    let store = MemoryLicenseKeyStore(LicenseTestKeyPair.vector)
    let license = LicenseController(store: store, verifier: revoking)
    guard case .revoked = license.state else { Issue.record("not revoked"); return }
    #expect(LicenseController(store: MemoryLicenseKeyStore("CD1-GARBAGE"), verifier: verifier).state == .invalid)

    #expect(!license.activate("nope"))
    license.remove()
    #expect(license.state == .none && store.key == nil && license.rejected == nil)
}

/// A Keychain that fails says so, never reads as "no license" silently or claims a key it didn't keep (Decision 62).
@Test @MainActor func aFailingKeychainSaysSo() {
    let unreadable = MemoryLicenseKeyStore(LicenseTestKeyPair.vector); unreadable.failReads = true
    let license = LicenseController(store: unreadable, verifier: verifier)
    #expect(license.state == .none && license.notice == .unreadable)

    let store = MemoryLicenseKeyStore(); store.failWrites = true
    let saving = LicenseController(store: store, verifier: verifier)
    #expect(!saving.activate(LicenseTestKeyPair.vector))
    #expect(saving.state == .none && saving.notice == .saveFailed && saving.rejected == nil)
    store.failWrites = false
    #expect(saving.activate(LicenseTestKeyPair.vector))
    #expect(saving.notice == nil)

    store.failRemoves = true
    let kept = saving.state
    saving.remove()
    #expect(saving.state == kept && saving.notice == .removeFailed && store.key != nil)
}

/// Settings' words for each state and notice (Decision 92: fragments, no full stop, curly apostrophes).
@Test func eachLicenseStateReadsAsSettingsShowsIt() {
    let license = License(id: LicenseTestKeyPair.vectorID, edition: .standard, macs: 3, issued: .distantPast)
    let one = License(id: LicenseTestKeyPair.vectorID, edition: .standard, macs: 1, issued: .distantPast)
    #expect(LicenseState.none.summary == "No license on this Mac")
    #expect(LicenseState.active(license).summary == "Licensed, up to 3 Macs")
    #expect(LicenseState.active(one).summary == "Licensed, up to 1 Mac")
    #expect(LicenseState.invalid.summary == "License key not valid")
    #expect(LicenseState.revoked(license).summary == "License key revoked")
    #expect(LicenseController.Notice.unreadable.message == "Couldn’t read the license key")
    #expect(LicenseController.Notice.saveFailed.message == "License key wasn’t saved")
    #expect(LicenseController.Notice.removeFailed.message == "License key wasn’t removed")
}

/// The Keychain item's names are stored keys: renaming either would lose every Mac's license key (#448).
@Test @MainActor func theKeychainItemKeepsItsNames() {
    #expect(KeychainLicenseKeyStore.service == "com.patrickbourget.CacheDrop.license")
    #expect(KeychainLicenseKeyStore.account == "license-key")
}
