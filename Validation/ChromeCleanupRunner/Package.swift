// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ChromeCleanupRunner", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/StillCore")],
    targets: [.executableTarget(name: "ChromeCleanupRunner", dependencies: [.product(name: "StillCore", package: "StillCore")])])
