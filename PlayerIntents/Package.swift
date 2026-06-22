// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "PlayerIntents",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    .library(
      name: "PlayerIntents",
      targets: ["PlayerIntents"]
    )
  ],
  dependencies: [
    .package(path: "../Models")
  ],
  targets: [
    .target(
      name: "PlayerIntents",
      dependencies: [
        .product(name: "Models", package: "Models")
      ]
    )
  ]
)
