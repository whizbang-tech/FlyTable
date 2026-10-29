// swift-tools-version: 6.0
import PackageDescription

// FlyTable: a headless table core with a custom-drawn native renderer behind a SwiftUI API.
// The floor matches FlyUI (macOS 15, iOS 18, visionOS 2). FlyUI depends on FlyTable, never the reverse.
let package = Package(
  name: "FlyTable",
  platforms: [.macOS(.v15), .iOS(.v18), .visionOS(.v2)],
  products: [
    .library(name: "FlyTableCore", targets: ["FlyTableCore"]),
    .library(name: "FlyTable", targets: ["FlyTable"]),
    .executable(name: "FlyTableGallery", targets: ["FlyTableGallery"]),
  ],
  targets: [
    .target(name: "FlyTableCore"),
    .target(name: "FlyTable", dependencies: ["FlyTableCore"]),
    .executableTarget(name: "FlyTableGallery", dependencies: ["FlyTable"]),
    .testTarget(name: "FlyTableCoreTests", dependencies: ["FlyTableCore"]),
    .testTarget(name: "FlyTableTests", dependencies: ["FlyTable", "FlyTableCore"]),
  ],
  swiftLanguageModes: [.v6]
)
