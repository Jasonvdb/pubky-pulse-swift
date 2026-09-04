// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PubkyPulse",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "PubkyPulse", targets: ["PubkyPulse"]),
    ],
    targets: [
        .target(
            name: "PubkyPulse",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(name: "PubkyPulseTests", dependencies: ["PubkyPulse"]),
    ]
)
