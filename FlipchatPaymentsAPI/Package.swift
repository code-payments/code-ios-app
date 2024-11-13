// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipchatPaymentsAPI",
    platforms: [
        .iOS(.v16),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "FlipchatPaymentsAPI",
            targets: ["FlipchatPaymentsAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "FlipchatPaymentsAPI",
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
