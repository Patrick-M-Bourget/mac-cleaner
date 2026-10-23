// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FilesystemFixtures", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../Packages/StillCore")], targets: [.executableTarget(name: "FilesystemFixtures", dependencies: [.product(name: "StillCore", package: "StillCore")])])
