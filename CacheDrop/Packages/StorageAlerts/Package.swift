// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "StorageAlerts", platforms: [.macOS(.v14)], products: [.library(name: "StorageAlerts", targets: ["StorageAlerts"])], targets: [.target(name: "StorageAlerts"), .testTarget(name: "StorageAlertsTests", dependencies: ["StorageAlerts"], resources: [.copy("Fixtures")])])
