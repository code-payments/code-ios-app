// swift-tools-version: 5.9
import PackageDescription

// Cross-platform test-vector GATE for logic that lives in FlipcashCore (Base58, and later key
// derivation, bonding curve, amounts). Asserts this repo's implementations reproduce the canonical
// fixtures in `code/test-vectors/` — the SAME fixtures the Android repo asserts against.
//
// Kept separate from `CrossPlatformVectors` (which tests standalone CodeCurves/ed25519) because
// FlipcashCore's transitive deps require macOS 13.3; mixing the two in one target conflicts on the
// macOS deployment target. macOS is listed so `swift test` runs the gate on the host in CI.
//
// Fixtures under Tests/.../Fixtures/ are synced from `code/test-vectors/` (single source of truth).
let package = Package(
    name: "FlipcashCoreVectors",
    platforms: [
        .macOS("14.0"), // FlipcashCore's transitive deps (BigDecimal 13.3, grpc/nio) need >= 13.3
        .iOS("18.0"),
    ],
    dependencies: [
        .package(path: "../FlipcashCore"),
        .package(url: "https://github.com/mgriebling/BigDecimal", from: "3.0.2"), // to assert curve values
    ],
    targets: [
        .testTarget(
            name: "FlipcashCoreVectorsTests",
            dependencies: [
                .product(name: "FlipcashCore", package: "FlipcashCore"),
                .product(name: "BigDecimal", package: "BigDecimal"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
