// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MWall",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mwall", targets: ["MWall"])
    ],
    targets: [
        .executableTarget(
            name: "MWall",
            path: "Sources/MWall"
        )
    ]
)
