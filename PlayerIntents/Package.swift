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
  targets: [
    .target(
      name: "PlayerIntents"
    )
  ]
)
