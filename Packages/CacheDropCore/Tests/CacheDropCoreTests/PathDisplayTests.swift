import Testing
import CacheDropCore

@Test func shortLocationNamesTheContainingFolderBriefly() {
    let home = "/Users/example"
    #expect(PathDisplay.shortLocation(of: "/Users/example/Projects", home: home) == "~")
    #expect(PathDisplay.shortLocation(of: "/Users/example/Workspace/app", home: home) == "~/Workspace")
    #expect(PathDisplay.shortLocation(of: "/Users/example/Work/Clients/Acme/site", home: home) == "…/Clients/Acme")
    #expect(PathDisplay.shortLocation(of: "/Volumes/Backup/Photos", home: home) == "/Volumes/Backup")
    #expect(PathDisplay.shortLocation(of: "/Data", home: home) == "/")
    #expect(PathDisplay.shortLocation(of: "/Users/example2/Docs", home: home) == "/Users/example2")
}
