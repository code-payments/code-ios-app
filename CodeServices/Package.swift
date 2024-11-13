// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeServices",
    platforms: [
        .iOS(.v16),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "CodeServices",
            targets: ["CodeServices"]
        ),
    ],
    dependencies: [
        .package(path: "../CodeCurves"),
        .package(path: "../CodeAPI"),
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "3.7.4"),
        .package(url: "https://github.com/karwa/swift-url", from: "0.4.2"),
        .package(url: "https://github.com/jedisct1/swift-sodium", from: "0.9.1"),
    ],
    targets: [
        .target(
            name: "CodeServices",
            dependencies: [
                .product(name: "CodeCurves", package: "CodeCurves"),
                .product(name: "CodeAPI", package: "CodeAPI"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "WebURL", package: "swift-url"),
                .product(name: "WebURLFoundationExtras", package: "swift-url"),
                .product(name: "Clibsodium", package: "swift-sodium"),
                .product(name: "Sodium", package: "swift-sodium"),
            ]
        ),
        .testTarget(
            name: "CodeServicesTests",
            dependencies: ["CodeServices"]
        ),
    ]
)
