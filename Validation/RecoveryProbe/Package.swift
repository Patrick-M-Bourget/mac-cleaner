// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RecoveryProbe", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../Packages/StillCore")], targets: [.executableTarget(name: "RecoveryProbe", dependencies: [.product(name: "StillCore", package: "StillCore")])])
