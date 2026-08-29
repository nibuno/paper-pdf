// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "PaperPDFPrototype",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "PaperPDFCore", targets: ["PaperPDFCore"]),
    .executable(name: "PaperPDFPrototype", targets: ["PaperPDFPrototype"]),
  ],
  targets: [
    .target(name: "PaperPDFCore"),
    .executableTarget(
      name: "PaperPDFPrototype",
      dependencies: ["PaperPDFCore"]
    ),
    .testTarget(
      name: "PaperPDFCoreTests",
      dependencies: ["PaperPDFCore"]
    ),
  ]
)
