// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeServices",
    platforms: [
        .iOS(.v15),
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
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "3.7.4")
    ],
    targets: [
        .target(
            name: "CodeServices",
            dependencies: [
                "ed25519",
                .product(name: "CodeAPI", package: "CodeAPI"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
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
