// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CacheDropCore", platforms: [.macOS(.v14)], products: [.library(name: "CacheDropCore", targets: ["CacheDropCore"])], targets: [.target(name: "CacheDropCore"), .testTarget(name: "CacheDropCoreTests", dependencies: ["CacheDropCore"])])
