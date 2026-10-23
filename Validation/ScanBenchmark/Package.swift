// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ScanBenchmark", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../Packages/StillCore")], targets: [.executableTarget(name: "ScanBenchmark", dependencies: [.product(name: "StillCore", package: "StillCore")])])
