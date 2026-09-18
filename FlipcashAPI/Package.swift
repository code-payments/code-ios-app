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
// A sync touches one package at a time, so FLIPCASH_PROTO_LOCAL_PACKAGES is required whenever
// FLIPCASH_PROTO_LOCAL is set: a comma-separated list of "ocp" / "flipcash2" (or their full
// directory names, case-insensitive) naming which package(s) go local. A package left out of
// the list keeps its pinned version, so an unrelated in-progress checkout of the other client
// repo can't break your build. Both packages together still works, just say so explicitly:
// FLIPCASH_PROTO_LOCAL_PACKAGES=ocp,flipcash2.
//
// Local mode drops the selected contract entries — one or both — from the tracked workspace
// Package.resolved. That is noise rather than a version change, since the pins below are
// exact, but restore it before committing:
//
//     git checkout -- Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
//
// Unset is the committed state, and CI never sets it, so release builds always resolve the
// pinned version below.
let protoLocalRoot = ProcessInfo.processInfo.environment["FLIPCASH_PROTO_LOCAL"]
    .map { ($0 as NSString).expandingTildeInPath }
    .flatMap { $0.isEmpty ? nil : $0 }

enum ContractPackage: String, CaseIterable {
    case ocp
    case flipcash2

    /// The client repo's directory name: the last path component under `FLIPCASH_PROTO_LOCAL`
    /// for a local checkout, and the GitHub repo name for the published one.
    var directoryName: String {
        switch self {
        case .ocp: return "ocp-client-protocol"
        case .flipcash2: return "flipcash2-client-protocol"
        }
    }

    var url: String {
        "https://github.com/code-payments/\(directoryName)"
    }

    /// The pinned version consumed when this package isn't building against a local checkout.
    var version: Version {
        switch self {
        case .ocp: return "0.5.0"
        case .flipcash2: return "0.10.0"
        }
    }

    /// Matches a `FLIPCASH_PROTO_LOCAL_PACKAGES` token, case-insensitive, accepting either the
    /// canonical short name or the client repo's full directory name.
    static func parse(_ token: String) -> ContractPackage? {
        switch token.lowercased() {
        case "ocp", "ocp-client-protocol": return .ocp
        case "flipcash2", "flipcash2-client-protocol": return .flipcash2
        default: return nil
        }
    }
}

let localPackages: Set<ContractPackage> = {
    guard protoLocalRoot != nil else {
        return []
    }
    let raw = ProcessInfo.processInfo.environment["FLIPCASH_PROTO_LOCAL_PACKAGES"] ?? ""
    let tokens = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !tokens.isEmpty else {
        fatalError("""
            FLIPCASH_PROTO_LOCAL_PACKAGES: required when FLIPCASH_PROTO_LOCAL is set. Export a \
            comma-separated list of which package(s) to build locally. Valid values: ocp, \
            ocp-client-protocol, flipcash2, flipcash2-client-protocol.
            """)
    }
    return Set(tokens.map { token in
        guard let package = ContractPackage.parse(token) else {
            fatalError("""
                FLIPCASH_PROTO_LOCAL_PACKAGES: unrecognized package '\(token)'. \
                Valid values: ocp, ocp-client-protocol, flipcash2, flipcash2-client-protocol.
                """)
        }
        return package
    })
}()

let contractDependencies: [Package.Dependency] = ContractPackage.allCases.map { package in
    if let protoLocalRoot, localPackages.contains(package) {
        return .package(path: "\(protoLocalRoot)/\(package.directoryName)")
    } else {
        return .package(url: package.url, exact: package.version)
    }
}

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
