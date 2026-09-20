//
//  StillImageLuminanceRenderer.swift
//  Flipcash
//

import Accelerate
import CoreGraphics

/// Renders crops of a still image into the tightly packed grey buffer `kikCodeScan` reads.
///
/// A class rather than a free function because it owns the drawing buffer. The search
/// renders hundreds of crops and each one is drawn over completely, so allocating and
/// zeroing a fresh buffer per crop is pure waste — at the largest crop the search allows it
/// is 10 MB of `memset` that `CGContext` immediately overwrites. One renderer per search
/// worker keeps a single buffer, grown to the largest crop that worker has drawn.
///
/// Not `Sendable`, deliberately: the buffer is reused across calls, so two tasks sharing one
/// renderer would draw over each other. Each worker makes its own.
///
/// `nonisolated` because the search runs off the main actor and the target isolates every
/// declaration to it by default.
nonisolated final class StillImageLuminanceRenderer {

    private var scratch: UnsafeMutableRawPointer?
    private var capacity: Int = 0

    init() {}

    deinit {
        scratch?.deallocate()
    }

    /// Renders `crop` at `renderedSide` and returns its luminance.
    ///
    /// `renderedSide` is the longest side of the output, so a small crop is scaled up to
    /// give the fixed-scale scanner something big enough to read. The shorter side keeps
    /// the crop's aspect ratio.
    ///
    /// The returned sample owns its bytes; only the intermediate colour buffer is reused.
    func sample(from image: CGImage, crop: CGRect, renderedSide: CGFloat) -> CodeExtractor.Sample? {
        let clamped = crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard
            clamped.width >= 1,
            clamped.height >= 1,
            let cropped = image.cropping(to: clamped)
        else {
            return nil
        }

        let scale = renderedSide / max(clamped.width, clamped.height)
        let width = max(Int((clamped.width * scale).rounded()), 1)
        let height = max(Int((clamped.height * scale).rounded()), 1)

        // Drawn as RGBA rather than grey so the luma weights below are ours, not
        // CoreGraphics'. `noneSkipLast` keeps it 4 bytes per pixel with no premultiplication
        // to undo.
        let rgba = buffer(ofAtLeast: width * height * 4)

        guard
            let context = CGContext(
                data: rgba,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        return CodeExtractor.Sample(
            width: width,
            height: height,
            data: Self.luminance(from: rgba, width: width, height: height)
        )
    }

    // MARK: - Buffer -

    /// The drawing buffer, grown when a crop needs more room. Never shrunk: the ladder
    /// mixes crop sizes, so a buffer that fits the largest fits everything after it.
    ///
    /// Uninitialized on purpose. The only reader is `CGContext`, which writes every byte of
    /// the region it draws into before anything reads it.
    private func buffer(ofAtLeast byteCount: Int) -> UnsafeMutableRawPointer {
        if let scratch, capacity >= byteCount {
            return scratch
        }

        scratch?.deallocate()

        let allocated = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        scratch = allocated
        capacity = byteCount
        return allocated
    }

    // MARK: - Luminance -

    /// BT.601 in the integer form Android uses: `(77r + 150g + 29b) >> 8`.
    ///
    /// Done as a matrix multiply rather than by hand, and not by drawing into a
    /// `CGColorSpaceCreateDeviceGray` context: that context is gamma-aware and rounds
    /// differently from Android, whereas the divisor of 256 here *is* the shift, so the
    /// bytes are the same ones Android computes. `StillImageLuminanceRendererTests` holds
    /// that equivalence down against the hand-written loop this replaced.
    private static func luminance(from rgba: UnsafeMutableRawPointer, width: Int, height: Int) -> Data {
        let count = width * height
        let destination = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)

        var source = vImage_Buffer(
            data: rgba,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
        )
        var planar = vImage_Buffer(
            data: destination,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width
        )

        // The fourth coefficient is the byte `noneSkipLast` leaves unused.
        let coefficients: [Int16] = [77, 150, 29, 0]
        coefficients.withUnsafeBufferPointer { matrix in
            _ = vImageMatrixMultiply_ARGB8888ToPlanar8(
                &source,
                &planar,
                matrix.baseAddress!,
                256,
                nil,
                0,
                // The search runs its own crops in parallel; vImage's tiling underneath
                // that would oversubscribe the cores rather than add any.
                vImage_Flags(kvImageDoNotTile)
            )
        }

        return Data(bytesNoCopy: destination, count: count, deallocator: .custom { pointer, _ in
            pointer.deallocate()
        })
    }
}
