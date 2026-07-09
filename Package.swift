// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PulpEditor",
    platforms: [
        // Current-generation floors only (macOS 26 / iOS 26): the editor is
        // TextKit 2-native and tracks modern AppKit/UIKit behavior; there is
        // no legacy-OS support target.
        .macOS(.v26),
        .iOS(.v26)
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
            path: "Tests/PulpTests",
            resources: [
                // .process (not .copy) flattens the file to the bundle root so
                // Bundle.module.url(forResource:withExtension:) resolves it on
                // iOS too — iOS does not search resource subdirectories.
                .process("Fixtures/content-derivation.json")
            ]
        )
    ]
)
