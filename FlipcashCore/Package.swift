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
        .package(path: "../CodeCurves"),
//        .package(path: "../FlipcashAPI"),
//        .package(path: "../FlipcashPaymentsAPI"),
    ],
    targets: [
        .target(
            name: "FlipcashCore",
            dependencies: [
                .product(name: "CodeCurves", package: "CodeCurves"),
                .product(name: "WebURL", package: "swift-url"),
                .product(name: "WebURLFoundationExtras", package: "swift-url"),
//                .product(name: "FlipcashAPI", package: "FlipcashAPI"),
//                .product(name: "FlipcashPaymentsAPI", package: "FlipcashPaymentsAPI"),
            ]
        ),
        .testTarget(
            name: "FlipcashCoreTests",
            dependencies: ["FlipcashCore"]
        ),
    ]
)

//let package = Package(
//    name: "FlipcashCore",
//    products: [
//        // Products define the executables and libraries a package produces, making them visible to other packages.
//        .library(
//            name: "FlipcashCore",
//            targets: ["FlipcashCore"]),
//    ],
//    targets: [
//        // Targets are the basic building blocks of a package, defining a module or a test suite.
//        // Targets can depend on other targets in this package and products from dependencies.
//        .target(
//            name: "FlipcashCore"),
//        .testTarget(
//            name: "FlipcashCoreTests",
//            dependencies: ["FlipcashCore"]
//        ),
//    ]
//)
