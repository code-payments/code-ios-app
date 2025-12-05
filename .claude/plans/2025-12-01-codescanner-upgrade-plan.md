# CodeScanner Upgrade & Swift Package Migration Plan

**Date:** 2025-12-01
**Goal:** Upgrade OpenCV to latest version and convert CodeScanner to a Swift Package

---

## Executive Summary

The CodeScanner project currently uses OpenCV 2.4.13.7 (released 2017) and is integrated as an Xcode sub-project with embedded framework. This plan outlines the steps to:

1. Upgrade OpenCV to 4.x (latest stable)
2. Convert to a Swift Package for modern dependency management
3. Maintain backward compatibility with existing Flipcash integration

---

## Current State

| Component | Current | Target |
|-----------|---------|--------|
| OpenCV | 2.4.13.7 (2017) | 4.9.x or 4.10.x |
| Build System | Xcode project + embedded framework | Swift Package |
| Framework Size | ~55MB | Optimized (minimal modules) |
| Swift Integration | Objective-C bridging | Swift-friendly C++ interop |

---

## Phase 1: OpenCV Upgrade (In-Place)

**Objective:** Update OpenCV while keeping the current Xcode project structure to isolate API migration issues.

### Step 1.1: Identify API Changes

OpenCV 2.x → 4.x breaking changes affecting scanner.cpp:

| 2.x API | 4.x Replacement |
|---------|-----------------|
| `CV_RETR_CCOMP` | `cv::RETR_CCOMP` |
| `CV_CHAIN_APPROX_SIMPLE` | `cv::CHAIN_APPROX_SIMPLE` |
| `CV_GRAY2RGB` | `cv::COLOR_GRAY2RGB` |
| `CV_ADAPTIVE_THRESH_MEAN_C` | `cv::ADAPTIVE_THRESH_MEAN_C` |
| `CV_THRESH_BINARY` / `CV_THRESH_BINARY_INV` | `cv::THRESH_BINARY` / `cv::THRESH_BINARY_INV` |
| `CV_RANSAC` | `cv::RANSAC` |
| `CV_8UC1`, `CV_8UC3`, `CV_64F` | `CV_8UC1`, `CV_8UC3`, `CV_64F` (unchanged) |

### Step 1.2: Build OpenCV 4.x for iOS

```bash
# Clone OpenCV
git clone https://github.com/opencv/opencv.git
cd opencv
git checkout 4.9.0  # or latest stable

# Build for iOS (creates opencv2.xcframework)
python3 platforms/apple/build_xcframework.py \
  --out ./build_ios \
  --iphoneos_archs arm64 \
  --iphonesimulator_archs arm64,x86_64 \
  --build_only_specified_archs \
  --without objc \
  --without java \
  --without python \
  --disable VIDEOIO \
  --disable HIGHGUI \
  --disable ML \
  --disable DNN \
  --disable PHOTO \
  --disable VIDEO \
  --disable STITCHING \
  --disable GAPI
```

**Modules to include:**
- core (required)
- imgproc (thresholding, contours, morphology)
- calib3d (homography)
- features2d (ellipse fitting)

**Modules to exclude:**
- highgui (only used for debug imwrite)
- video, videoio, ml, dnn, photo, stitching, gapi, objc, java, python

### Step 1.3: Update scanner.cpp

```cpp
// Before (2.x)
findContours(mat, contours, hierarchy, CV_RETR_CCOMP, CV_CHAIN_APPROX_SIMPLE, Point2i(0, 0));
cvtColor(greyscale, rgb_colour, CV_GRAY2RGB);
threshold(greyscale, whitish, 170, 255, THRESH_BINARY);
adaptiveThreshold(greyscale, blackish, 255, CV_ADAPTIVE_THRESH_MEAN_C, CV_THRESH_BINARY_INV, 19, 5);
Mat H = findHomography(object_points, scene_points, CV_RANSAC);

// After (4.x)
findContours(mat, contours, hierarchy, cv::RETR_CCOMP, cv::CHAIN_APPROX_SIMPLE, Point2i(0, 0));
cvtColor(greyscale, rgb_colour, cv::COLOR_GRAY2RGB);
threshold(greyscale, whitish, 170, 255, cv::THRESH_BINARY);
adaptiveThreshold(greyscale, blackish, 255, cv::ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY_INV, 19, 5);
Mat H = findHomography(object_points, scene_points, cv::RANSAC);
```

### Step 1.4: Update Header Includes

```cpp
// Before (2.x style)
#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/calib3d/calib3d.hpp>
#include <opencv2/features2d/features2d.hpp>

// After (4.x style - simpler)
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/features2d.hpp>
// Remove highgui unless keeping debug output
```

### Step 1.5: Test In-Place

1. Replace `CodeScanner/Frameworks/opencv2.framework` with new xcframework
2. Update Xcode project to link xcframework instead of framework
3. Fix any remaining compilation errors
4. Run existing tests
5. Test scanning with sample images

---

## Phase 2: Swift Package Conversion

**Objective:** Convert CodeScanner from Xcode project to Swift Package.

### Step 2.1: Create Package Structure

```
CodeScanner/
├── Package.swift
├── Sources/
│   ├── CodeScanner/
│   │   ├── include/
│   │   │   ├── module.modulemap
│   │   │   ├── Code.h           # Public ObjC header
│   │   │   ├── kikcode_scan.h   # C API
│   │   │   └── kikcodes.h       # C API
│   │   ├── Code.mm
│   │   └── src/
│   │       ├── scanner.cpp
│   │       ├── scanner.h
│   │       ├── kikcodes.cpp
│   │       ├── kikcode_scan.cpp
│   │       ├── kikcode_encoding.cpp
│   │       ├── kikcode_encoding.h
│   │       ├── kikcode_constants.h
│   │       └── zxing/
│   │           └── ... (Reed-Solomon)
│   └── CCodeScanner/           # Optional: Pure C wrapper for Swift
│       ├── include/
│       │   └── CCodeScanner.h
│       └── CCodeScanner.c
├── Tests/
│   └── CodeScannerTests/
│       └── CodeScannerTests.swift
└── Frameworks/
    └── opencv2.xcframework     # XCFramework (not .framework)
```

### Step 2.2: Create Package.swift

```swift
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
            path: "Sources/CodeScanner",
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
                .unsafeFlags(["-w"])  // Suppress warnings temporarily
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
            dependencies: ["CodeScanner"]
        )
    ],
    cxxLanguageStandard: .cxx17
)
```

### Step 2.3: Create Module Map

```modulemap
// Sources/CodeScanner/include/module.modulemap
framework module CodeScanner {
    umbrella header "Code.h"

    export *
    module * { export * }

    link framework "opencv2"
    link framework "Accelerate"
}
```

### Step 2.4: Update Main Project

In `Code.xcodeproj`:

1. Remove CodeScanner.xcodeproj sub-project reference
2. Remove CodeScanner.framework from "Frameworks, Libraries, and Embedded Content"
3. Add CodeScanner package dependency:
   - File → Add Package Dependencies
   - Add local package: `../CodeScanner` (or remote URL if published)
4. Add `CodeScanner` library to Flipcash target

---

## Phase 3: Testing & Validation

### Step 3.1: Unit Tests

Convert existing placeholder tests to actual tests:

```swift
import Testing
@testable import CodeScanner

@Suite("CodeScanner Tests")
struct CodeScannerTests {

    @Test("Encode and decode round-trip")
    func encodeDecodeRoundTrip() {
        let payload = Data(repeating: 0xAB, count: 20)
        let encoded = KikCodes.encode(payload)
        let decoded = KikCodes.decode(encoded)

        #expect(decoded == payload)
    }

    @Test("Scan detects code in sample image")
    func scanSampleImage() {
        // Load test image with known code
        let sample = loadTestSample()

        let result = KikCodes.scan(
            sample.data,
            width: sample.width,
            height: sample.height,
            quality: .high
        )

        #expect(result != nil)
    }
}
```

### Step 3.2: Integration Tests

1. Build Flipcash with new CodeScanner package
2. Test camera scanning in simulator
3. Test with various image qualities
4. Test with inverted (dark center) codes

### Step 3.3: Performance Tests

Compare scan times between old and new OpenCV:

```swift
@Test("Scan performance within acceptable range")
func scanPerformance() async {
    let sample = loadTestSample()

    let clock = ContinuousClock()
    var totalDuration = Duration.zero
    let iterations = 100

    for _ in 0..<iterations {
        let start = clock.now
        _ = KikCodes.scan(sample.data, width: sample.width, height: sample.height, quality: .high)
        totalDuration += clock.now - start
    }

    let avgMs = Double(totalDuration.components.attoseconds) / 1e15 / Double(iterations)
    #expect(avgMs < 50) // Should complete in under 50ms
}
```

---

## Phase 4: Cleanup & Optimization (Optional)

### Step 4.1: Remove JNI Files

Delete Android-specific files:
- `kikcode_scan_jni.h`
- `kikcode_scan_jni.cpp`
- `kikcode_encoding_jni.h`
- `kikcode_encoding_jni.cpp`

### Step 4.2: Fix Compiler Warnings

Remove `-w` flag and fix warnings properly:
- Update deprecated C++ constructs
- Add proper const correctness
- Fix implicit conversions

### Step 4.3: Consider Alternative Approaches

For future optimization:
- Use Metal/Accelerate for image processing
- Use Vision framework for contour detection
- Pre-compute lookup tables at compile time

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| OpenCV API incompatibility | Phase 1 isolates API changes before package conversion |
| Framework size regression | Build with minimal modules, compare sizes |
| Scan accuracy changes | Test with known sample images, compare results |
| Build time increase | Pre-build OpenCV xcframework, cache in package |
| Swift Package linking issues | Test on multiple Xcode versions |

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 1: OpenCV Upgrade | 1-2 days |
| Phase 2: Swift Package | 1-2 days |
| Phase 3: Testing | 1 day |
| Phase 4: Cleanup | 0.5-1 day |
| **Total** | **3.5-6 days** |

---

## Success Criteria

- [ ] Builds successfully as Swift Package
- [ ] All existing scanning functionality preserved
- [ ] Encode/decode round-trip works correctly
- [ ] Scan performance within 20% of baseline
- [ ] Framework size reduced (target: <30MB)
- [ ] No XCTest usage (use Swift Testing)
- [ ] Clean build with no warnings (optional but preferred)
