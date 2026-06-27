// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "FlipcashCore",
            targets: ["FlipcashCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "4.1.4"),
        .package(url: "https://github.com/mgriebling/BigDecimal", from: "3.0.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(path: "../CodeCurves"),
        .package(path: "../FlipcashAPI"),
    ],
    targets: [
        .target(
            name: "FlipcashCore",
            dependencies: [
                .product(name: "CodeCurves", package: "CodeCurves"),
                .product(name: "BigDecimal", package: "BigDecimal"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "FlipcashAPI", package: "FlipcashAPI"),
            ],
            resources: [
                .copy("Resources/discrete_pricing_table.bin"),
                .copy("Resources/discrete_cumulative_table.bin"),
            ]
        ),
        .testTarget(
            name: "FlipcashCoreTests",
            dependencies: [
                "FlipcashCore",
                .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
            ]
        ),
    ]
)
