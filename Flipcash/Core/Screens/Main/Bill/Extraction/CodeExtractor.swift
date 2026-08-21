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
}

// MARK: - Sample -

extension CodeExtractor {
    struct Sample {
        let width: Int
        let height: Int
        let data: Data
    }
}
