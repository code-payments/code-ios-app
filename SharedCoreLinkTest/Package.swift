// swift-tools-version: 5.9
import PackageDescription

// Dev-only harness that proves the KMMBridge-published SharedCore SPM package links and its exported
// Kotlin symbols are callable from Swift. It consumes the `Package.swift` that KMMBridge generates at
// the root of the Android repo (the KMP repo) as a local path dependency — the same package iOS will
// consume by Git URL + version once KMMBridge publishes releases (`./gradlew :kmp:shared-core:kmmBridgePublish`).
//
// Refresh the framework after Kotlin changes:
//   (in code-android-app) ./gradlew :kmp:shared-core:spmDevBuild
let package = Package(
    name: "SharedCoreLinkTest",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    dependencies: [
        // The KMMBridge-generated package at the Android repo root (siblings under `code/`).
        .package(path: "../../code-android-app"),
    ],
    targets: [
        .testTarget(
            name: "SharedCoreLinkTestTests",
            dependencies: [
                .product(name: "SharedCore", package: "code-android-app"),
            ]
        ),
    ]
)
