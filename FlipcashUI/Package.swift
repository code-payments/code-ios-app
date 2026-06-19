// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashUI",
    platforms: [
        .iOS(.v18),
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
        .package(url: "https://github.com/ekazaev/ChatLayout", from: "2.4.2"),
    ],
    targets: [
        .target(
            name: "FlipcashUI",
            dependencies: [
                .product(name: "FlipcashCore", package: "FlipcashCore"),
                .product(name: "ChatLayout", package: "ChatLayout", condition: .when(platforms: [.iOS])),
            ],
            resources: [
                .process("Assets")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
