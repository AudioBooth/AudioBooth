// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "API",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(
      name: "API",
      targets: ["API"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.13.1"),
    .package(url: "https://github.com/auth0/SimpleKeychain.git", exact: "1.3.0"),
    .package(url: "https://github.com/kean/Nuke.git", exact: "13.0.6"),
    .package(url: "https://github.com/kean/Pulse.git", exact: "5.2.2"),
  ],
  targets: [
    .target(
      name: "API",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SimpleKeychain", package: "SimpleKeychain"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "Pulse", package: "Pulse"),
      ],
    ),
    .testTarget(
      name: "APITests",
      dependencies: ["API"],
    ),
  ]
)
