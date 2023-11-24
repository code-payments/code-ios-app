// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeAPI",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "CodeAPI",
            targets: ["CodeAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "CodeAPI",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
            ],
            exclude: [
                "proto",
                "proto_deps",
            ]
        ),
        .testTarget(
            name: "CodeAPITests",
            dependencies: ["CodeAPI"]
        ),
    ]
)
