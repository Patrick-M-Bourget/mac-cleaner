// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ICloudProbe", platforms: [.macOS(.v14)], products: [.executable(name: "icloud-probe", targets: ["icloud-probe"])], targets: [.target(name: "CloudProbe"), .executableTarget(name: "icloud-probe", dependencies: ["CloudProbe"]), .testTarget(name: "CloudProbeTests", dependencies: ["CloudProbe"])])
