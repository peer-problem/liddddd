// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Liddddd",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "LidddddApp", targets: ["LidddddApp"]),
    .executable(name: "LidddddHelper", targets: ["LidddddHelper"]),
  ],
  targets: [
    .target(name: "LidddddCore"),
    .executableTarget(
      name: "LidddddApp",
      dependencies: ["LidddddCore"]
    ),
    .executableTarget(
      name: "LidddddHelper",
      dependencies: ["LidddddCore"]
    ),
    .testTarget(
      name: "LidddddCoreTests",
      dependencies: ["LidddddCore"]
    ),
  ]
)
