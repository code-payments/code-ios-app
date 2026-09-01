// swift-tools-version: 5.9
import PackageDescription

// Cross-platform test-vector GATE (Track-B/C safety net). Asserts this repo's native crypto
// reproduces the canonical fixtures in `code/test-vectors/` — the SAME fixtures the Android repo
// asserts against, so the two apps cannot silently diverge on crypto they both must get identical.
//
// Fixtures under Tests/.../Fixtures/ are synced from the orchestrator's `code/test-vectors/`
// (single source of truth; regenerate via `code/test-vectors/gen_ed25519.py`).
//
// macOS is listed so `swift test` runs the gate on the host in CI without a simulator; the crypto
// under test is plain C (CodeCurves), platform-independent.
let package = Package(
    name: "CrossPlatformVectors",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    dependencies: [
        .package(path: "../CodeCurves"),
    ],
    targets: [
        .testTarget(
            name: "CrossPlatformVectorsTests",
            dependencies: ["CodeCurves"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
