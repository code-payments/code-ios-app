// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FlipcashCore",
            targets: ["FlipcashCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/karwa/swift-url", from: "0.4.2"),
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "4.1.4"),
        .package(url: "https://github.com/mgriebling/BigDecimal", from: "3.0.2"),
        .package(path: "../CodeCurves"),
        .package(path: "../FlipcashAPI"),
        .package(path: "../FlipcashCoreAPI"),
    ],
    targets: [
        .target(
            name: "FlipcashCore",
            dependencies: [
                .product(name: "CodeCurves", package: "CodeCurves"),
                .product(name: "WebURL", package: "swift-url"),
                .product(name: "WebURLFoundationExtras", package: "swift-url"),
                .product(name: "BigDecimal", package: "BigDecimal"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "FlipcashAPI", package: "FlipcashAPI"),
                .product(name: "FlipcashCoreAPI", package: "FlipcashCoreAPI"),
            ],
            resources: [
                .copy("Resources/discrete_pricing_table.bin"),
                .copy("Resources/discrete_cumulative_table.bin"),
            ]
        ),
        .testTarget(
            name: "FlipcashCoreTests",
            dependencies: ["FlipcashCore"]
        ),
    ]
)
