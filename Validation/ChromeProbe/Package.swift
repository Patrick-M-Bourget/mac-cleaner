// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ChromeProbe", platforms: [.macOS(.v14)], products: [.library(name: "ChromeProbe", targets: ["ChromeProbe"])], targets: [.target(name: "ChromeProbe"), .testTarget(name: "ChromeProbeTests", dependencies: ["ChromeProbe"])])
