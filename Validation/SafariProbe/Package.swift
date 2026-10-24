// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SafariProbe", platforms: [.macOS(.v14)], products: [.library(name: "SafariProbe", targets: ["SafariProbe"])], targets: [.target(name: "SafariProbe"), .testTarget(name: "SafariProbeTests", dependencies: ["SafariProbe"])])
