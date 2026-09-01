// swift-tools-version: 5.9
import PackageDescription

// Cross-platform test-vector GATE (Track-B/C safety net). Asserts the ed25519 this app signs
// with reproduces the canonical fixtures in `code/test-vectors/` — the SAME fixtures the Android
// repo asserts against, so the two apps cannot silently diverge on crypto they both must get
// identical.
//
// Fixtures under Tests/.../Fixtures/ are synced from the orchestrator's `code/test-vectors/`
// (single source of truth; regenerate via `code/test-vectors/gen_ed25519.py`).
//
// iOS only, and run on a simulator rather than `swift test` on the host: the implementation under
// test is no longer a host-buildable C package but the shared Kotlin reached through
// `SharedCoreKit`, whose XCFramework ships iOS slices only. That is the point of the gate now —
// it exercises the framework exactly as FlipcashCore consumes it, which the Kotlin-side
// `Ed25519VectorTest` on the same fixtures does not.
let package = Package(
    name: "CrossPlatformVectors",
    platforms: [
        .iOS(.v15),
    ],
    dependencies: [
        .package(path: "/Users/bmc/dev/bmcreations/code/code-android-app/kmp/shared-core/spm"),
    ],
    targets: [
        .testTarget(
            name: "CrossPlatformVectorsTests",
            dependencies: [.product(name: "SharedCoreKit", package: "spm")],
            resources: [.copy("Fixtures")]
        ),
    ]
)
