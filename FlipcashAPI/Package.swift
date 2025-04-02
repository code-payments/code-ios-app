// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FlipcashAPI",
            targets: ["FlipcashAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.22.0"),
    ],
    targets: [
        .target(
            name: "FlipcashAPI",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
            ],
            exclude: [
                "Core/proto",
                "Core/proto_deps",
                "Payments/proto",
                "Payments/proto_deps",
            ]
        ),
    ]
)
