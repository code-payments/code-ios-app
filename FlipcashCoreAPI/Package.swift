// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashCoreAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FlipcashCoreAPI",
            targets: ["FlipcashCoreAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.22.0"),
    ],
    targets: [
        .target(
            name: "FlipcashCoreAPI",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
            ],
            exclude: [
                "proto",
                "proto_deps",
            ]
        ),
    ]
)
