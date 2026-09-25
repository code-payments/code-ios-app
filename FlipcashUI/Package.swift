// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// `FLIPCASH_SHARED_CORE_LOCAL` swaps the pinned package for a path dependency into a
// `code-android-app` checkout. `FlipcashCore/Package.swift` carries the full rationale and the
// loop; the one thing to know here is that all three manifests consuming `SharedCoreKit` have to
// move together, because SPM resolves one version for the whole graph.
let sharedCoreLocalRoot = ProcessInfo.processInfo.environment["FLIPCASH_SHARED_CORE_LOCAL"]
    .map { ($0 as NSString).expandingTildeInPath }
    .flatMap { $0.isEmpty ? nil : $0 }

// A path dependency takes its identity from the directory's basename rather than the `Package(name:)`
// inside it, so under the override the package is `spm`. Product references have to follow.
let sharedCorePackage = sharedCoreLocalRoot == nil ? "flipcash-shared-core-spm" : "spm"

let sharedCore: Package.Dependency = {
    if let sharedCoreLocalRoot {
        return .package(path: "\(sharedCoreLocalRoot)/kmp/shared-core/spm")
    }
    return .package(url: "https://github.com/code-payments/flipcash-shared-core-spm", .upToNextMinor(from: "0.8.0"))
}()

let package = Package(
    name: "FlipcashUI",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "FlipcashUI",
            targets: ["FlipcashUI"]
        ),
    ],
    dependencies: [
        .package(path: "../FlipcashCore"),
        .package(url: "https://github.com/ekazaev/ChatLayout", from: "2.4.2"),
        .package(url: "https://github.com/ra1028/DifferenceKit", from: "1.3.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "8.3.0"),
        sharedCore,
    ],
    targets: [
        .target(
            name: "FlipcashUI",
            dependencies: [
                .product(name: "FlipcashCore", package: "FlipcashCore"),
                .product(name: "ChatLayout", package: "ChatLayout", condition: .when(platforms: [.iOS])),
                .product(name: "DifferenceKit", package: "DifferenceKit"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SharedCoreKit", package: sharedCorePackage),
            ],
            resources: [
                .process("Assets")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
