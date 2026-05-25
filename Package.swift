// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PulpEditor",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "Pulp", targets: ["Pulp"])
    ],
    targets: [
        .target(
            name: "Pulp",
            path: "Sources/Pulp"
        ),
        .testTarget(
            name: "PulpTests",
            dependencies: ["Pulp"],
            path: "Tests/PulpTests"
        )
    ]
)
