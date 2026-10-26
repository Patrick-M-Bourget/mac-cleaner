import Foundation
import Testing
import StillCore

@Test func shortLocationIsTheScopeNameAndTheFoldersBelowIt() {
    let scope = URL(fileURLWithPath: "/Users/a/Library/Containers/x/Data/tmp/Projects")
    #expect(ShortLocation.of(scope.appendingPathComponent("old.zip"), in: scope) == "Projects")
    #expect(ShortLocation.of(scope.appendingPathComponent("Renders/final.mp4"), in: scope) == "Projects › Renders")
    #expect(ShortLocation.of(URL(fileURLWithPath: "/elsewhere/Box/f"), in: scope) == "Box")
}
