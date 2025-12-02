# CodeScanner Specification

This document provides a complete technical specification of the CodeScanner project, a C++ library for encoding, decoding, and scanning circular "Kik Codes" (custom 2D barcodes). Originally developed as a cross-platform solution for iOS and Android.

---

## Overview

CodeScanner is a framework that:
1. **Encodes** 20-byte payloads into a 35-byte format with Reed-Solomon error correction
2. **Decodes** 35-byte encoded data back to the original 20-byte payload
3. **Scans** camera frames to detect and extract Kik Codes from images using OpenCV

The codes are circular 2D barcodes with:
- A central finder circle
- An orientation ring with 9 finder points
- 5 concentric data rings

---

## Project Structure

```
CodeScanner/
├── CodeScanner.xcodeproj     # Xcode project (builds as framework)
├── CodeScanner/
│   ├── CodeScanner.h         # Framework umbrella header
│   ├── Code.h                # Objective-C public interface
│   ├── Code.mm               # Objective-C++ wrapper implementation
│   ├── Info.plist
│   └── src/
│       ├── scanner.h/.cpp        # Core OpenCV scanning algorithm
│       ├── kikcodes.h/.cpp       # C API wrapper for encoding/decoding
│       ├── kikcode_scan.h/.cpp   # C API wrapper for scanning
│       ├── kikcode_encoding.h/.cpp  # KikCode classes (encoding/decoding logic)
│       ├── kikcode_constants.h   # Constants
│       ├── *_jni.h/.cpp          # Android JNI bindings (not used on iOS)
│       └── zxing/                # Reed-Solomon implementation from ZXing
│           ├── Exception.h/.cpp
│           ├── ZXing.h
│           └── common/
│               ├── Array.h
│               ├── Counted.h
│               └── reedsolomon/
│                   ├── GenericGF.h/.cpp
│                   ├── GenericGFPoly.h/.cpp
│                   ├── ReedSolomonEncoder.h/.cpp
│                   ├── ReedSolomonDecoder.h/.cpp
│                   └── ReedSolomonException.h/.cpp
├── CodeScannerTests/
│   └── CodeScannerTests.swift    # Tests (currently minimal)
└── Frameworks/
    └── opencv2.xcframework       # OpenCV 4.10.0 (~100MB, arm64 device + arm64/x86_64 simulator)
```

---

## Dependencies

### OpenCV 4.10.0

**Current Version:** 4.10.0 (updated December 2025)

**Size:** ~100MB (XCFramework: arm64 device + arm64/x86_64 simulator)

**Modules Used:**
- `core` - Basic data structures (Mat, Point, Size, etc.)
- `imgproc` - Image processing (threshold, contours, morphological ops)
- `calib3d` - Camera calibration (findHomography, perspectiveTransform)
- `features2d` - Feature detection (fitEllipse, moments)
- `highgui` - I/O utilities (only for debug image writing)

**Key OpenCV Functions Used:**
```cpp
// Image processing
cv::threshold()
cv::adaptiveThreshold()
cv::GaussianBlur()
cv::addWeighted()          // For unsharp mask
cv::dilate()
cv::findContours()
cv::bitwise_and()
cv::cvtColor()
cv::resize()

// Geometry
cv::fitEllipse()
cv::moments()
cv::arcLength()
cv::contourArea()
cv::convexHull()

// Perspective transform
cv::findHomography()
cv::perspectiveTransform()
cv::invert()

// Drawing (debug only)
cv::ellipse()
cv::circle()
cv::drawContours()
cv::imwrite()
```

### ZXing (Subset)

A minimal subset of ZXing's Reed-Solomon implementation for error correction:
- Uses `GenericGF::QR_CODE_FIELD_256` (GF(2^8) for QR codes)
- 13-byte ECC can correct ~6 byte errors

---

## Data Format

### Code Structure

```
Total: 35 bytes (280 bits)
├── ECC (13 bytes)  - Reed-Solomon error correction
└── Data (22 bytes)
    ├── Header (2 bytes)
    │   ├── Type (5 bits)     - Code type (1=Username, 2=Remote, 3=Group)
    │   ├── Colour (6 bits)   - Color code
    │   └── Extra (5 bits)    - Type-specific extra data
    └── Payload (20 bytes)    - Type-specific payload
```

### Payload Types

| Type | Value | Description |
|------|-------|-------------|
| Username | 1 | 6-bit encoded username + 2-byte nonce |
| Remote | 2 | 20-byte arbitrary payload |
| Group | 3 | 20-byte invite code |

### Current Usage (Flipcash)

Flipcash uses the **Remote** type to encode payment data:

```
Payload (20 bytes):
├── Type (1 byte)      - Payment kind (cash, gift card, etc.)
├── Currency (1 byte)  - Currency code index
├── Amount (8 bytes)   - Quarks (micro-currency units)
└── Nonce (10 bytes)   - Random nonce
```

---

## Scanning Algorithm

The scanning algorithm (in `scanner.cpp`) follows these steps:

### 1. Preprocessing
- Apply unsharp mask (2x) to enhance edges
- Threshold image at value 170 to create binary image

### 2. Contour Detection
- Find all contours in thresholded image
- Filter by area, circularity, convexity, and inertia ratio

### 3. Ellipse Fitting
- Fit ellipses to candidate contours
- Filter to retain only strong candidates

### 4. Orientation Ring Detection
For each candidate ellipse:
- Create annular mask around the ellipse
- Find 9 finder points in the orientation ring
- Match angular spacing against known pattern
- Determine code orientation

### 5. Data Extraction
If orientation ring found:
- Compute homography from known finder positions
- Map all data point positions through homography
- Sample image at each data point
- Reconstruct 35-byte data

### 6. Error Correction
- Apply Reed-Solomon decoding
- Correct up to 6 byte errors

### Quality Levels

The scanner supports different quality levels affecting image resolution:

| Level | Max Edge Size |
|-------|---------------|
| LOW (0) | 240px |
| MEDIUM (3) | 320px |
| HIGH (8) | 480px |
| BEST (10) | 960px |

---

## iOS Integration

### Framework Structure

CodeScanner builds as a dynamic framework that exposes:

**Public Header:** `Code.h`

```objc
@interface KikCodes : NSObject

+ (NSData *)encode:(NSData *)data;      // Encode 20-byte payload
+ (NSData *)decode:(NSData *)data;      // Decode 35-byte data

+ (nullable NSData *)scan:(NSData *)data
                    width:(NSInteger)width
                   height:(NSInteger)height;

+ (nullable NSData *)scan:(NSData *)data
                    width:(NSInteger)width
                   height:(NSInteger)height
                  quality:(KikCodesScanQuality)quality;

@end
```

### Usage in Flipcash

**CodeExtractor.swift** uses CodeScanner to:
1. Extract Y plane from camera sample buffers
2. Call `KikCodes.scan()` to detect codes
3. Decode result with `KikCodes.decode()`
4. Parse decoded data into `CashCode.Payload`

**CashCode.Payload+Encoding.swift** uses:
- `KikCodes.encode()` to generate scannable code data
- `KikCodes.decode()` to parse scanned data

### Xcode Project Integration

- CodeScanner.xcodeproj is embedded as a sub-project
- Framework is linked to both Code and Flipcash targets
- OpenCV framework path: `$(PROJECT_DIR)/CodeScanner/Frameworks`

---

## API Reference

### Objective-C (Code.h)

```objc
typedef NS_ENUM(NSInteger, KikCodesScanQuality) {
    KikCodesScanQualityLow    = 0,
    KikCodesScanQualityMedium = 2,
    KikCodesScanQualityHigh   = 7,
    KikCodesScanQualityBest   = 10
};

@interface KikCodes : NSObject

// Encode 20-byte payload to 35-byte code data
+ (NSData *)encode:(NSData *)data;

// Decode 35-byte code data to 20-byte payload
+ (NSData *)decode:(NSData *)data;

// Scan grayscale image for code
+ (nullable NSData *)scan:(NSData *)data
                    width:(NSInteger)width
                   height:(NSInteger)height
                  quality:(KikCodesScanQuality)quality;

@end
```

### C API (kikcodes.h)

```c
int kikCodeEncodeRemote(
    unsigned char *out_data,
    const unsigned char *key,
    const unsigned int colour_code);

int kikCodeDecode(
    const unsigned char *data,
    unsigned int *out_type,
    KikCodePayload *out_payload,
    unsigned int *out_colour_code);
```

### C API (kikcode_scan.h)

```c
int kikCodeScan(
    const unsigned char *image,
    unsigned int width,
    unsigned int height,
    unsigned int device_quality,
    unsigned char *out_data,
    unsigned int *out_x,
    unsigned int *out_y,
    unsigned int *out_scale,
    double *out_transform);
```

---

## Known Issues & Limitations

1. **JNI Files**: Android JNI files are included but not used on iOS

2. **Tests**: Minimal test coverage (just placeholder tests)

3. **Compiler Warnings**: All .cpp files compiled with `-w` flag to suppress warnings

4. **Framework Size**: ~100MB for OpenCV XCFramework (includes multiple architectures)

---

## Upgrade History

### OpenCV 4.10.0 Migration (December 2025)

**Completed:** API migration from OpenCV 2.x to 4.x

Key changes made:
- Updated includes: `<opencv2/core.hpp>` instead of `<opencv2/core/core.hpp>`
- Replaced macros with cv:: namespace enums:
  - `CV_RETR_CCOMP` → `cv::RETR_CCOMP`
  - `CV_CHAIN_APPROX_SIMPLE` → `cv::CHAIN_APPROX_SIMPLE`
  - `CV_GRAY2RGB` → `cv::COLOR_GRAY2RGB`
  - `CV_ADAPTIVE_THRESH_MEAN_C` → `cv::ADAPTIVE_THRESH_MEAN_C`
  - `CV_THRESH_BINARY_INV` → `cv::THRESH_BINARY_INV`
  - `CV_RANSAC` → `cv::RANSAC`
- Wrapped debug `imwrite()` calls in `#if DEBUGGING` preprocessor guards
- Replaced old framework with XCFramework built with minimal modules

**OpenCV Modules Included:**
- core, imgproc, calib3d, features2d, flann, imgcodecs, objdetect

**OpenCV Modules Excluded:**
- highgui, video, videoio, ml, dnn, photo, stitching, gapi, objc, java, python

---

## Building OpenCV

### Automated Build Script

A build script is provided at `CodeScanner/Scripts/build_opencv.sh` that automates the entire process.

**Usage:**
```bash
# Build latest OpenCV version
./Scripts/build_opencv.sh

# Build specific version
./Scripts/build_opencv.sh --version 4.10.0

# Clean rebuild (removes cached source)
./Scripts/build_opencv.sh --clean
```

**Requirements:**
- macOS with Xcode installed
- CMake 3.18.5+ (`brew install cmake`)
- Python 3
- ~10GB free disk space for build
- ~10 minutes build time on M-series Mac

### Manual Build Process

If you need to build manually, follow these steps:

#### 1. Clone OpenCV
```bash
git clone --depth 1 --branch 4.10.0 https://github.com/opencv/opencv.git /tmp/opencv
```

#### 2. Build XCFramework
```bash
cd /tmp/opencv
python3 platforms/apple/build_xcframework.py \
  --out /tmp/opencv_build \
  --iphoneos_archs arm64 \
  --iphonesimulator_archs arm64,x86_64 \
  --build_only_specified_archs \
  --without objc \
  --without java \
  --without python \
  --without video \
  --without videoio \
  --without highgui \
  --without ml \
  --without dnn \
  --without photo \
  --without stitching \
  --without gapi \
  --without ts \
  --without world
```

#### 3. Fix iOS Framework Structure (Critical!)

The OpenCV build script creates macOS-style "versioned bundles" with symlinks:
```
opencv2.framework/
├── Headers -> Versions/Current/Headers
├── Modules -> Versions/Current/Modules
├── opencv2 -> Versions/Current/opencv2
├── Resources -> Versions/Current/Resources
└── Versions/
    ├── A/
    │   ├── Headers/
    │   ├── Info.plist
    │   └── opencv2
    └── Current -> A
```

**iOS requires "shallow bundles"** (flat structure with Info.plist at root):
```
opencv2.framework/
├── Headers/
├── Info.plist          # MUST be at root level
├── Modules/
│   └── module.modulemap
├── opencv2
└── Resources/
```

**Flatten each framework inside the XCFramework:**
```bash
flatten_framework() {
    local fw="$1"

    # Remove symlinks
    rm -f "$fw/Headers" "$fw/Modules" "$fw/opencv2" "$fw/Resources"

    # Copy contents from Versions/A to root
    cp -R "$fw/Versions/A/"* "$fw/"
    rm -rf "$fw/Versions"

    # Move Info.plist to root (critical for iOS!)
    if [ -f "$fw/Resources/Info.plist" ]; then
        mv "$fw/Resources/Info.plist" "$fw/Info.plist"
    fi
}

# Apply to both platforms
flatten_framework "opencv2.xcframework/ios-arm64/opencv2.framework"
flatten_framework "opencv2.xcframework/ios-arm64_x86_64-simulator/opencv2.framework"
```

#### 4. Add Module Maps

Create `Modules/module.modulemap` in each framework:
```
framework module opencv2 {
    umbrella header "opencv2.hpp"
    export *
    module * { export * }
    link framework "Accelerate"
    link framework "CoreGraphics"
    link framework "CoreVideo"
    link framework "QuartzCore"
    link framework "UIKit"
}
```

#### 5. Install
```bash
cp -R /tmp/opencv_build/opencv2.xcframework CodeScanner/Frameworks/
```

### Common Build Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "shallow bundles" error | Info.plist not at framework root | Run flatten script |
| "module 'opencv2' not found" | Missing modulemap | Add module.modulemap |
| Build timeout | Building too many modules | Use `--without` flags |
| "unsupported architecture" | Wrong arch flags | Check `--iphoneos_archs` |

---

## Future Considerations

### Optimization Opportunities

1. Use Metal/Accelerate for image processing
2. Further reduce OpenCV module subset
3. Consider Vision framework for contour detection
