import Foundation
import Darwin
import Testing
@testable import CacheDropCore

/// #463: the in-use check reads only file-backed regions when macOS gives exactly the files the full walk does. This process
/// maps many files, so it is the check CacheDrop runs on itself before trusting the faster reading; a macOS that changed the
/// flavor fails here, and the app falls back to the full walk.
/// Other tests map files in this process meanwhile, so the readings are compared as the app compares them, not once.
@Test func fileBackedRegionsGiveTheSameMappedFilesAsTheFullWalk() throws {
    #expect(try #require(SystemInUseSnapshot.mappedPaths(getpid(), flavor: SystemInUseSnapshot.fileBackedRegions)).isEmpty == false)
    #expect(SystemInUseSnapshot.fileBackedRegionsAgree)
}
