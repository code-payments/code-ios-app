// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipchatAPI",
    platforms: [
        .iOS(.v16),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "FlipchatAPI",
            targets: ["FlipchatAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "FlipchatAPI",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
            ],
            exclude: [
                "proto",
                "proto_deps",
            ]
        ),
        .testTarget(
            name: "FlipchatAPITests",
            dependencies: ["FlipchatAPI"]
        ),
    ]
)
