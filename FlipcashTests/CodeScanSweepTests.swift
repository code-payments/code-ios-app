//
//  CodeScanSweepTests.swift
//  FlipcashTests
//

import AVFoundation
import CoreVideo
import SwiftUI
import Testing
import UIKit

import CodeScanner
@testable import Flipcash
@testable import FlipcashUI

/// The iOS half of the scanner harness, mirroring `KikCodeScanTest` in the Android repo
/// (`vendor/kik/scanner/src/androidTest/.../KikCodeScanTest.kt`).
///
/// Both platforms feed the same C++ scanner — the eight files under `CodeScanner/src` are
/// byte-identical to Android's `vendor/kik/scanner/src/main/cpp` — so the only place the two can
/// disagree is the ~20 lines of pixel-buffer glue each one wraps it in. That glue is what this
/// exercises: a code is rendered, written into a real `CVPixelBuffer`, and pulled back out through
/// `CodeExtractor` exactly the way a capture frame would be.
///
/// The interesting axis is capture width. CoreVideo aligns plane rows to 64 bytes, so 1920 comes
/// back tightly packed (stride 1920) while 1440 comes back padded (stride 1472). `CodeExtractor`
/// used to read its stride from `CVPixelBufferGetBytesPerRow`, which reports a whole-buffer value
/// for planar formats, and never unpadded — so the padded widths below are the cases that were
/// silently sheared.
@MainActor
@Suite("Code Scan Sweep")
struct CodeScanSweepTests {

    /// Chosen so the sweep covers both sides of CoreVideo's 64-byte row alignment.
    static let resolutions: [(width: Int, height: Int)] = [
        (1920, 1080), // 64-aligned -> tightly packed
        (1440, 1080), // padded to a 1472-byte stride
        (1000, 750),  // padded to a 1024-byte stride
    ]

    static let codeScales: [CGFloat] = [0.5, 0.7, 0.9]

    /// `kikCodeEncodeRemote` takes a 20-byte payload.
    static let payload = Data((0..<20).map { UInt8(($0 &* 7 &+ 11) % 251) })

    // MARK: - Sweep -

    @Test("rendered codes decode at every resolution and code scale")
    func sweepRenderedCodesAcrossResolutionsAndScales() throws {
        var decoded = 0
        var attempted = 0

        for resolution in Self.resolutions {
            for scale in Self.codeScales {
                attempted += 1

                let buffer = try Self.makeFrame(
                    width: resolution.width,
                    height: resolution.height,
                    codeScale: scale
                )

                if let payload = Self.scan(buffer) {
                    #expect(payload == Self.payload)
                    decoded += 1
                } else {
                    Issue.record(
                        """
                        no decode at \(resolution.width)x\(resolution.height) scale=\(scale) \
                        stride=\(CVPixelBufferGetBytesPerRowOfPlane(buffer, 0))
                        """
                    )
                }
            }
        }

        #expect(decoded == attempted, "sweep: \(decoded)/\(attempted) decoded")
    }

    /// The regression that matters: a padded capture width must decode to the same payload as a
    /// packed one. Before the stride fix the padded frames sheared by 32-64 bytes per row and
    /// decoded to nothing.
    @Test("padded and packed capture widths decode identically")
    func paddedAndPackedWidthsDecodeIdentically() throws {
        let packed = try Self.makeFrame(width: 1920, height: 1080, codeScale: 0.7)
        let padded = try Self.makeFrame(width: 1440, height: 1080, codeScale: 0.7)

        #expect(CVPixelBufferGetBytesPerRowOfPlane(packed, 0) == 1920, "expected a packed plane")
        #expect(CVPixelBufferGetBytesPerRowOfPlane(padded, 0) > 1440, "expected a padded plane")

        #expect(Self.scan(packed) == Self.payload)
        #expect(Self.scan(padded) == Self.payload)
    }

    // MARK: - Packing rule -

    /// Mirrors `LuminancePlaneTest` in `:libs:codes:kikcode` commonTest. The two implementations
    /// have to agree byte for byte, so they are checked against the same geometries and the same
    /// `(i % 251)` fill.
    @Test("packing rule matches the shared Kotlin rule")
    func packingRuleMatchesSharedRule() {
        let geometries: [(width: Int, height: Int, rowStride: Int)] = [
            (640, 480, 640),
            (640, 480, 768),
            (1280, 720, 1280),
            (1280, 720, 1408),
            (1920, 1080, 1920),
            (1920, 1080, 2048),
        ]

        for geometry in geometries {
            let plane = [UInt8]((0..<(geometry.rowStride * geometry.height)).map { UInt8($0 % 251) })

            let packed = plane.withUnsafeBytes { raw in
                CodeExtractor.luminanceData(
                    base: raw.baseAddress!,
                    width: geometry.width,
                    height: geometry.height,
                    rowStride: geometry.rowStride
                )
            }

            #expect(
                packed.count == geometry.width * geometry.height,
                "wrong length at \(geometry.width)x\(geometry.height)/\(geometry.rowStride)"
            )

            for row in 0..<geometry.height {
                for column in 0..<geometry.width {
                    let expected = plane[row * geometry.rowStride + column]
                    let actual = packed[row * geometry.width + column]
                    guard expected == actual else {
                        Issue.record(
                            """
                            mismatch at (\(column),\(row)) for \
                            \(geometry.width)x\(geometry.height)/\(geometry.rowStride): \
                            expected \(expected), got \(actual)
                            """
                        )
                        return
                    }
                }
            }
        }
    }

    /// The fast path exists to avoid copying ~2MB per frame, so assert it really is a view onto the
    /// plane rather than a copy of it.
    @Test("tightly packed planes are handed over without copying")
    func tightlyPackedPlanesAreNotCopied() {
        let width = 1920
        let height = 1080
        var plane = [UInt8](repeating: 0, count: width * height)

        plane.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!
            let data = CodeExtractor.luminanceData(
                base: base,
                width: width,
                height: height,
                rowStride: width
            )

            // Mutating the plane must be visible through `data` if nothing was copied.
            base.assumingMemoryBound(to: UInt8.self)[42] = 0xAB
            #expect(data[42] == 0xAB, "packed plane should be a no-copy view of the buffer")
        }
    }

    // MARK: - Helpers -

    /// Runs a frame through the real extraction path and returns the decoded payload.
    private static func scan(_ buffer: CVPixelBuffer) -> Data? {
        let extractor = CodeExtractor()
        return extractor.withLuminanceSample(from: makeSampleBuffer(buffer)) { sample in
            guard
                let scanned = KikCodes.scan(
                    sample.data,
                    width: sample.width,
                    height: sample.height,
                    quality: .best
                )
            else {
                return nil
            }
            return KikCodes.decode(scanned)
        }
    }

    /// Renders a code into the luminance plane of a real 420 pixel buffer, letting CoreVideo pick
    /// the row stride so the padded cases are the ones the camera would actually hand us.
    private static func makeFrame(width: Int, height: Int, codeScale: CGFloat) throws -> CVPixelBuffer {
        let image = try renderCode(side: CGFloat(min(width, height)) * codeScale)

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &buffer
        )

        guard status == kCVReturnSuccess, let buffer else {
            throw ScanHarnessError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            throw ScanHarnessError.missingPlane
        }

        let rowStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

        // Drawing straight into the plane at its own stride is what makes the padded cases real:
        // CoreGraphics writes the padding bytes the camera would have left there.
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: rowStride,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ScanHarnessError.contextCreationFailed
        }

        // Dark field, matching the rendered code's polarity and Android's harness.
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let cgImage = image.cgImage {
            let side = image.size.width
            context.draw(
                cgImage,
                in: CGRect(
                    x: (CGFloat(width) - side) / 2,
                    y: (CGFloat(height) - side) / 2,
                    width: side,
                    height: side
                )
            )
        }

        // Neutral chroma, so the frame is a plausible greyscale image end to end.
        if CVPixelBufferGetPlaneCount(buffer) > 1, let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            memset(chroma, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1))
        }

        return buffer
    }

    /// Renders `CodeView`, which draws the code together with the centre badge.
    ///
    /// Polarity is not cosmetic. The detector finds a candidate code by thresholding for *bright*
    /// blobs and fitting an ellipse to the centre badge, and only then looks at the ring around it
    /// to decide whether the marks are inverted. So the badge has to be the bright part: light
    /// marks and a light badge on a dark field, which is also what the bill draws and what
    /// Android's harness renders. Black-on-white leaves the badge as a dark hole and nothing is
    /// ever detected.
    private static func renderCode(side: CGFloat) throws -> UIImage {
        let encoded = KikCodes.encode(payload)

        let renderer = ImageRenderer(
            content: CodeView(data: encoded)
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(Color.black)
        )
        renderer.scale = 1.0

        guard let image = renderer.uiImage else {
            throw ScanHarnessError.renderFailed
        }
        return image
    }

    private static func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription!,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer!
    }

    enum ScanHarnessError: Error {
        case pixelBufferCreationFailed(CVReturn)
        case missingPlane
        case contextCreationFailed
        case renderFailed
    }
}
