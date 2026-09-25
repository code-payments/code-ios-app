// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// `FLIPCASH_SHARED_CORE_LOCAL` points at a `code-android-app` checkout and swaps the pinned
// package below for a path dependency into that checkout's `kmp/shared-core/spm`, so a change to
// `:kmp:shared-core` — including the Swift facade under `Sources/SharedCoreKit` — can be tried
// from an iOS build without publishing a version to consume it:
//
//     cd code-android-app
//     ./gradlew :kmp:shared-core:assembleSharedCoreReleaseXCFramework
//     export FLIPCASH_SHARED_CORE_LOCAL=~/dev/bmcreations/code/code-android-app
//     xed ../code-ios-app
//
// Xcode inherits the environment of whatever launched it, so it has to be started from a shell
// that exported the variable rather than from the Dock. SwiftPM re-evaluates this manifest when
// the variable changes, so switching back needs no clean — but the assemble task has to be re-run
// after every Kotlin edit, because the override points at a file on disk and SwiftPM has no way to
// know it went stale. The full loop is the orchestrator's `docs/shared-core-local-development.md`.
//
// All three manifests that consume `SharedCoreKit` read this — `FlipcashCore`, `FlipcashUI` and
// `CrossPlatformVectors` — and they have to move together. SPM resolves one version for the whole
// graph, so a graph with a path dependency in one manifest and the remote in another fails to
// resolve, with a message about conflicting requirements that does not name the cause.
//
// For the same reason, `SharedCoreKit` must not be added to a target's package dependencies inside
// `Code.xcodeproj`: that reference resolves under identity `flipcash-shared-core-spm` and nothing
// an environment variable can reach rewrites it, so the two identities collide on duplicate
// targets. An app-target import belongs behind a `FlipcashCore` or `FlipcashUI` declaration.
//
// Local mode drops the pinned entry from the tracked workspace `Package.resolved` and changes its
// `originHash`, because a path dependency has no revision to pin. Restore it before committing:
//
//     git checkout -- Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
//
// Unset is the committed state, and CI never sets it, so release builds always resolve the pinned
// version below.
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
    return .package(url: "https://github.com/code-payments/flipcash-shared-core-spm", .upToNextMinor(from: "0.9.0"))
}()

let package = Package(
    name: "FlipcashCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "FlipcashCore",
            targets: ["FlipcashCore"]
        ),
        .library(
            name: "FlipcashStore",
            targets: ["FlipcashStore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/marmelroy/PhoneNumberKit", from: "4.1.4"),
        .package(url: "https://github.com/mgriebling/BigDecimal", from: "3.0.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(path: "../FlipcashAPI"),
        sharedCore,
        // Branch-pinned to match the app project's own reference to the same fork. SPM resolves one
        // version of it for the whole graph, so the two have to agree.
        .package(url: "https://github.com/dbart01/SQLite.swift", branch: "master"),
    ],
    targets: [
        .target(
            name: "FlipcashCore",
            dependencies: [
                .product(name: "BigDecimal", package: "BigDecimal"),
                .product(name: "PhoneNumberKit", package: "PhoneNumberKit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "FlipcashAPI", package: "FlipcashAPI"),
                .product(name: "SharedCoreKit", package: sharedCorePackage),
            ],
            resources: [
                .copy("Resources/discrete_pricing_table.bin"),
                .copy("Resources/discrete_cumulative_table.bin"),
            ]
        ),
        // The SQLite store, shared by the app and the notification service extension. It is a
        // separate target rather than part of `FlipcashCore` so that everything depending on the
        // models does not also pull in SQLite.
        .target(
            name: "FlipcashStore",
            dependencies: [
                "FlipcashCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SQLite", package: "SQLite.swift"),
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
