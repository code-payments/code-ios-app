// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashAPI",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "FlipcashAPI",
            targets: ["FlipcashAPI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/code-payments/ocp-client-protocol", exact: "0.1.0"),
        .package(url: "https://github.com/code-payments/flipcash2-client-protocol", exact: "0.1.0"),
    ],
    targets: [
        .target(
            name: "FlipcashAPI",
            dependencies: [
                .product(name: "OCPClientProtocol", package: "ocp-client-protocol"),
                .product(name: "Flipcash2ClientProtocol", package: "flipcash2-client-protocol"),
            ]
        ),
    ]
)
