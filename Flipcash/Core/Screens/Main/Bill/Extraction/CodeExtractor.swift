//
//  CodeExtractor.swift
//  Code
//
//  Created by Dima Bart on 2021-01-26.
//

import AVKit
import CodeScanner
import FlipcashUI
import FlipcashCore

class CodeExtractor: CameraSessionExtractor {
    
    private var container = RedundancyContainer<Data>(threshold: 1)
    
    required init() {}

    func extract(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> ScannedCode? {
        // The scan runs inside withLuminanceSample so the sample's zero-copy view of the plane
        // stays valid -- the base address is only guaranteed while the pixel buffer is locked.
        withLuminanceSample(from: sampleBuffer) { sample in
            Self.processSample(
                sample: sample,
                quality: .best,
                container: &container
            )
        }
    }
    
    private static func processSample(sample: Sample, quality: KikCodesScanQuality) -> (Data, ScannedCode)? {
        guard let data = KikCodes.scan(sample.data, width: sample.width, height: sample.height, quality: quality) else {
            return nil
        }

        let result = KikCodes.decode(data)

        guard let payload = ScannedCode(data: result) else {
            return nil
        }

        return (result, payload)
    }

    private static func processSample(sample: Sample, quality: KikCodesScanQuality, container: inout RedundancyContainer<Data>) -> ScannedCode? {
        if let (data, payload) = processSample(sample: sample, quality: quality) {
            container.insert(data)
            
            if let _ = container.value {
                container.reset()
                return payload
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    /// Vends the frame's luminance (Y) plane as a `Sample`, tightly packed the way `kikCodeScan`
    /// expects, and calls `body` with it.
    ///
    /// Internal rather than private so `CodeScanSweepTests` can drive it with synthesized frames.
    ///
    /// The sample is only valid for the duration of `body`: when the plane is already tightly
    /// packed its `data` is a no-copy view of the locked pixel buffer, which CoreVideo only
    /// guarantees between lock and unlock.
    func withLuminanceSample<T>(
        from sampleBuffer: CMSampleBuffer,
        _ body: (Sample) -> T?
    ) -> T? {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            return nil
        }

        // The capture format is planar 420, so these must be read per-plane.
        // CVPixelBufferGetBytesPerRow reports a whole-buffer value for planar formats -- at
        // 1920x1080 it returns 2884 rather than the plane's actual 1920 -- which both over-claims
        // the buffer's length and hides the row padding below.
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

        let sample = Sample(
            width: width,
            height: height,
            data: Self.luminanceData(base: base, width: width, height: height, rowStride: rowStride)
        )

        return body(sample)
    }

    /// Produces the tightly packed `width * height` buffer `kikCodeScan` reads.
    ///
    /// CoreVideo aligns plane rows to 64 bytes, so a capture width that is not a multiple of 64
    /// arrives padded -- 1440 wide comes back with a 1472-byte stride. Handing that straight to the
    /// scanner shears the image by a growing offset per row. Widths that are already 64-aligned
    /// (1920 among them, which is why `.hd1920x1080` has always worked) need no copy at all.
    ///
    /// This mirrors `LuminancePlane` in the shared Kotlin module, which Android applies to the same
    /// decision; there is no pixel-stride term because plane 0 of a 420 buffer is always one byte
    /// per pixel.
    static func luminanceData(
        base: UnsafeRawPointer,
        width: Int,
        height: Int,
        rowStride: Int
    ) -> Data {
        let scannedByteCount = width * height

        guard rowStride != width else {
            return Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: base),
                count: scannedByteCount,
                deallocator: .none
            )
        }

        var data = Data(count: scannedByteCount)
        data.withUnsafeMutableBytes { destination in
            guard let destination = destination.baseAddress else { return }
            for row in 0..<height {
                memcpy(
                    destination.advanced(by: row * width),
                    base.advanced(by: row * rowStride),
                    width
                )
            }
        }
        return data
    }

    /// Renders a crop of a still image into the tightly packed buffer `kikCodeScan` reads.
    ///
    /// Internal for the same reason as ``withLuminanceSample(from:_:)``: the tests drive it
    /// with synthesized images.
    ///
    /// The conversion is done by hand rather than by drawing into a `CGColorSpaceCreateDeviceGray`
    /// context, because that applies a gamma-aware conversion whose rounding differs from
    /// Android's. Both platforms use the integer BT.601 form so that one fixture image
    /// decodes the same way on both.
    ///
    /// `renderedSide` is the longest side of the output, so a small crop is scaled up to
    /// give the fixed-scale scanner something big enough to read. The shorter side keeps
    /// the crop's aspect ratio.
    /// `nonisolated` because the gallery search that calls this runs off the main actor,
    /// and the target isolates every declaration to it by default.
    nonisolated static func luminanceSample(
        from image: CGImage,
        crop: CGRect,
        renderedSide: CGFloat
    ) -> Sample? {
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard
            clamped.width >= 1,
            clamped.height >= 1,
            let cropped = image.cropping(to: clamped)
        else {
            return nil
        }

        let longestSide = max(clamped.width, clamped.height)
        let scale = renderedSide / longestSide
        let width = max(Int((clamped.width * scale).rounded()), 1)
        let height = max(Int((clamped.height * scale).rounded()), 1)

        // Drawn as RGBA rather than grey so the luma weights below are ours, not
        // CoreGraphics'. `noneSkipLast` keeps it 4 bytes per pixel with no premultiplication
        // to undo.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard
                let base = raw.baseAddress,
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else {
            return nil
        }

        var luminance = Data(count: width * height)
        luminance.withUnsafeMutableBytes { destination in
            guard let destination = destination.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            for index in 0..<(width * height) {
                let offset = index * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                // BT.601, integer form. Mirrors `KikCodeScanTest.renderFrame` on Android.
                destination[index] = UInt8((77 * red + 150 * green + 29 * blue) >> 8)
            }
        }

        return Sample(width: width, height: height, data: luminance)
    }
}

// MARK: - Sample -

extension CodeExtractor {
    struct Sample {
        let width: Int
        let height: Int
        let data: Data
    }
}
