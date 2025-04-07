// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlipcashUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FlipcashUI",
            targets: ["FlipcashUI"]
        ),
    ],
    dependencies: [
        .package(path: "../FlipcashCore"),
    ],
    targets: [
        .target(
            name: "FlipcashUI",
            dependencies: [
                .product(name: "FlipcashCore", package: "FlipcashCore"),
            ],
            resources: [
                .process("Assets")
            ]
        ),
        .testTarget(
            name: "FlipcashUITests",
            dependencies: ["FlipcashUI"]
        ),
    ]
)

//let package = Package(
//    name: "FlipcashUI",
//    products: [
//        // Products define the executables and libraries a package produces, making them visible to other packages.
//        .library(
//            name: "FlipcashUI",
//            targets: ["FlipcashUI"]),
//    ],
//    targets: [
//        // Targets are the basic building blocks of a package, defining a module or a test suite.
//        // Targets can depend on other targets in this package and products from dependencies.
//        .target(
//            name: "FlipcashUI"),
//        .testTarget(
//            name: "FlipcashUITests",
//            dependencies: ["FlipcashUI"]
//        ),
//    ]
//)
