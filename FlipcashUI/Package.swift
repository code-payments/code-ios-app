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
        // A slice binary truncated to 0 bytes otherwise fails much later, as a link or resolve
        // error that points at SwiftPM caches rather than the file. Every slice directory has to
        // hold a non-empty binary; the macOS one is a symlink, so it is resolved before sizing.
        let xcframework = "\(sharedCoreLocalRoot)/kmp/shared-core/build/XCFrameworks/release/SharedCore.xcframework"
        let fileManager = FileManager.default
        let slices = ((try? fileManager.contentsOfDirectory(atPath: xcframework)) ?? []).filter {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: "\(xcframework)/\($0)", isDirectory: &isDirectory) && isDirectory.boolValue
        }
        let binaries = slices.isEmpty ? [xcframework] : slices.map { "\(xcframework)/\($0)/SharedCore.framework/SharedCore" }
        for binary in binaries {
            let resolved = (binary as NSString).resolvingSymlinksInPath
            let size = ((try? fileManager.attributesOfItem(atPath: resolved))?[.size] as? NSNumber)?.int64Value ?? 0
            if slices.isEmpty || size == 0 {
                fatalError("SharedCore slice is empty: \(binary). Reassemble with ./gradlew :kmp:shared-core:assembleSharedCoreReleaseXCFramework")
            }
        }
        return .package(path: "\(sharedCoreLocalRoot)/kmp/shared-core/spm")
    }
    return .package(url: "https://github.com/code-payments/flipcash-shared-core-spm", .upToNextMinor(from: "0.19.0"))
}()

let package = Package(
    name: "FlipcashUI",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        // Dynamic for the same reason as FlipcashCore: one copy shared by the app and extensions.
        .library(
            name: "FlipcashUI",
            type: .dynamic,
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
                // No direct `SharedCoreKit` edge: FlipcashCore re-exports it, and linking it here
                // too would statically copy SharedCore into this dynamic framework as well.
            ],
            resources: [
                .process("Assets"),
                .copy("Resources/emoji_catalog.json"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
