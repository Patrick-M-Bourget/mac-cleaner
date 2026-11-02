// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CacheDropCore", platforms: [.macOS(.v14)],
                      products: [.library(name: "CacheDropCore", targets: ["CacheDropCore"]),
                                 // The read-only command line (#626).
                                 .executable(name: "cachedrop", targets: ["cachedrop"])],
                      targets: [.target(name: "CacheDropCore"),
                                .executableTarget(name: "cachedrop", dependencies: ["CacheDropCore"]),
                                .testTarget(name: "CacheDropCoreTests", dependencies: ["CacheDropCore"], resources: [.copy("Fixtures")])])
