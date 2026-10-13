// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SSHT", platforms: [.macOS(.v14)], products: [.executable(name: "SSHT", targets: ["SSHT"])], targets: [.executableTarget(name: "SSHT", resources: [.copy("Resources/Figma")]), .testTarget(name: "SSHTTests", dependencies: ["SSHT"], path: "Tests")])
