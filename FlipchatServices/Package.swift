// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipchatServices",
    platforms: [
        .iOS(.v16),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "FlipchatServices",
            targets: ["FlipchatServices"]
        ),
    ],
    dependencies: [
        .package(path: "../FlipchatAPI"),
        .package(path: "../CodeServices"),
        .package(path: "../FlipchatPaymentsAPI"),
    ],
    targets: [
        .target(
            name: "FlipchatServices",
            dependencies: [
                .product(name: "FlipchatAPI", package: "FlipchatAPI"),
                .product(name: "CodeServices", package: "CodeServices"),
                .product(name: "FlipchatPaymentsAPI", package: "FlipchatPaymentsAPI"),
            ]
        ),
        .testTarget(
            name: "FlipchatServicesTests",
            dependencies: ["FlipchatServices"]
        ),
    ]
)
