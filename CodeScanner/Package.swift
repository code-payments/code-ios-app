// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeScanner",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CodeScanner",
            targets: ["CodeScanner"]
        )
    ],
    targets: [
        .target(
            name: "CodeScanner",
            dependencies: ["opencv2"],
            path: "CodeScanner",
            exclude: [
                "Info.plist"
            ],
            sources: [
                "Code.mm",
                "src/scanner.cpp",
                "src/kikcodes.cpp",
                "src/kikcode_scan.cpp",
                "src/kikcode_encoding.cpp",
                "src/zxing/Exception.cpp",
                "src/zxing/common/IllegalArgumentException.cpp",
                "src/zxing/common/reedsolomon/GenericGF.cpp",
                "src/zxing/common/reedsolomon/GenericGFPoly.cpp",
                "src/zxing/common/reedsolomon/ReedSolomonDecoder.cpp",
                "src/zxing/common/reedsolomon/ReedSolomonEncoder.cpp",
                "src/zxing/common/reedsolomon/ReedSolomonException.cpp"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("src/zxing"),
                .headerSearchPath("src/zxing/common"),
                .headerSearchPath("src/zxing/common/reedsolomon"),
                .unsafeFlags(["-w"])
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia")
            ]
        ),
        .binaryTarget(
            name: "opencv2",
            path: "Frameworks/opencv2.xcframework"
        ),
        .testTarget(
            name: "CodeScannerTests",
            dependencies: ["CodeScanner"],
            path: "CodeScannerTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
