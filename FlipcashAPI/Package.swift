// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// The contract packages are normally consumed at a pinned version, which means trying a
// proto change would mean publishing one. Set FLIPCASH_PROTO_LOCAL to the directory that
// holds ocp-client-protocol/ and flipcash2-client-protocol/ to build against those
// checkouts instead:
//
//     export FLIPCASH_PROTO_LOCAL=~/dev/bmcreations/code
//     xed .
//
// Xcode inherits the environment of whatever launched it, so it has to be started from a
// shell that exported the variable rather than from the Dock. SwiftPM re-evaluates this
// manifest when the variable changes, so switching back needs no clean.
//
// Local mode drops the two contract entries from the tracked workspace Package.resolved.
// That is noise rather than a version change, since the pins below are exact, but restore it
// before committing:
//
//     git checkout -- Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
//
// Unset is the committed state, and CI never sets it, so release builds always resolve the
// pinned version below.
let protoLocalRoot = ProcessInfo.processInfo.environment["FLIPCASH_PROTO_LOCAL"]
    .map { ($0 as NSString).expandingTildeInPath }
    .flatMap { $0.isEmpty ? nil : $0 }

let contractDependencies: [Package.Dependency] = protoLocalRoot.map { root in
    [
        .package(path: "\(root)/ocp-client-protocol"),
        .package(path: "\(root)/flipcash2-client-protocol"),
    ]
} ?? [
    .package(url: "https://github.com/code-payments/ocp-client-protocol", exact: "0.3.0"),
    .package(url: "https://github.com/code-payments/flipcash2-client-protocol", exact: "0.4.0"),
]

let package = Package(
    name: "FlipcashAPI",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "FlipcashAPI",
            targets: ["FlipcashAPI"]
        ),
    ],
    dependencies: contractDependencies,
    targets: [
        .target(
            name: "FlipcashAPI",
            dependencies: [
                .product(name: "OCPClientProtocol", package: "ocp-client-protocol"),
                .product(name: "Flipcash2ClientProtocol", package: "flipcash2-client-protocol"),
            ]
        ),
    ]
)
