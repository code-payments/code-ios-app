// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeUI",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "CodeUI",
            targets: ["CodeUI"]
        ),
    ],
    dependencies: [
        .package(path: "../CodeServices"),
    ],
    targets: [
        .target(
            name: "CodeUI",
            dependencies: [
                .product(name: "CodeServices", package: "CodeServices"),
            ],
            resources: [
                .process("Assets")
            ]
        ),
        .testTarget(
            name: "CodeUITests",
            dependencies: ["CodeUI"]
        ),
    ]
)
