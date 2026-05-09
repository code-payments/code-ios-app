// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FlipcashUI",
            targets: ["FlipcashUI"]
        ),
    ],
    dependencies: [
        .package(path: "../FlipcashCore"),
    ],
    targets: [
        .target(
            name: "FlipcashUI",
            dependencies: [
                .product(name: "FlipcashCore", package: "FlipcashCore"),
            ],
            resources: [
                .process("Assets")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "FlipcashUITests",
            dependencies: ["FlipcashUI"]
        ),
    ]
)
