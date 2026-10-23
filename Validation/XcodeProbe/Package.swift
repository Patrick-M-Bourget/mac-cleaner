// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "XcodeProbe", platforms: [.macOS(.v14)], products: [.library(name: "XcodeProbe", targets: ["XcodeProbe"])], targets: [.target(name: "XcodeProbe"), .testTarget(name: "XcodeProbeTests", dependencies: ["XcodeProbe"])])
