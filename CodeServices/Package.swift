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
            targets: ["CodeServices", "ed25519"]
        ),
    ],
    dependencies: [
        .package(path: "../CodeAPI"),
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "3.7.4"),
        .package(url: "https://github.com/karwa/swift-url", from: "0.4.1"),
        .package(url: "https://github.com/jedisct1/swift-sodium", from: "0.9.1"),
    ],
    targets: [
        .target(
            name: "CodeServices",
            dependencies: [
                "ed25519",
                .product(name: "CodeAPI", package: "CodeAPI"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "WebURL", package: "swift-url"),
                .product(name: "WebURLFoundationExtras", package: "swift-url"),
                .product(name: "Clibsodium", package: "swift-sodium"),
                .product(name: "Sodium", package: "swift-sodium"),
            ]
        ),
        .target(
            name: "ed25519",
            dependencies: []
        ),
        .testTarget(
            name: "CodeServicesTests",
            dependencies: ["CodeServices"]
        ),
    ]
)
