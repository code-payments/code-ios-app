//
//  StillImageLuminanceRendererTests.swift
//  FlipcashTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Flipcash

/// The renderer converts colour to grey with a vImage matrix multiply. Android computes the
/// same bytes with a hand-written integer BT.601 loop, and one fixture image has to decode
/// the same way on both, so this suite pins the matrix to that loop rather than to a
/// tolerance.
@Suite("Still Image Luminance Renderer")
struct StillImageLuminanceRendererTests {

    @Test("the matrix multiply is byte-for-byte the integer BT.601 loop")
    func matchesTheHandWrittenLoop() throws {
        let side = 64
        let rgba = Self.randomPixels(count: side * side * 4)
        let image = try #require(Self.makeImage(rgba: rgba, side: side))

        let expected = Self.handWrittenLuminance(rgba: rgba, count: side * side)

        let sample = try #require(
            StillImageLuminanceRenderer().sample(
                from: image,
                crop: CGRect(x: 0, y: 0, width: side, height: side),
                renderedSide: CGFloat(side)
            )
        )

        #expect(sample.width == side)
        #expect(sample.height == side)
        #expect(Array(sample.data) == expected)
    }

    @Test("a reused renderer returns the same bytes as a fresh one")
    func reuseDoesNotLeakBetweenCrops() throws {
        // The buffer is reused and never cleared, so a smaller crop drawn after a larger one
        // is the case where stale bytes would show up.
        let image = try #require(Self.makeImage(rgba: Self.randomPixels(count: 256 * 256 * 4), side: 256))
        let renderer = StillImageLuminanceRenderer()

        let large = CGRect(x: 0, y: 0, width: 256, height: 256)
        let small = CGRect(x: 32, y: 32, width: 48, height: 48)

        _ = renderer.sample(from: image, crop: large, renderedSide: 256)
        let reused = try #require(renderer.sample(from: image, crop: small, renderedSide: 48))
        let fresh = try #require(
            StillImageLuminanceRenderer().sample(from: image, crop: small, renderedSide: 48)
        )

        #expect(reused.data == fresh.data)
    }

    // MARK: - Helpers -

    /// Deterministic noise: a failure has to be reproducible to be worth reporting.
    static func randomPixels(count: Int) -> [UInt8] {
        var seed: UInt64 = 0x5DEECE66D
        return (0..<count).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8((seed >> 33) & 0xFF)
        }
    }

    static func handWrittenLuminance(rgba: [UInt8], count: Int) -> [UInt8] {
        (0..<count).map { index in
            let offset = index * 4
            let red = Int(rgba[offset])
            let green = Int(rgba[offset + 1])
            let blue = Int(rgba[offset + 2])
            return UInt8((77 * red + 150 * green + 29 * blue) >> 8)
        }
    }

    static func makeImage(rgba: [UInt8], side: Int) -> CGImage? {
        var pixels = rgba
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            else {
                return nil
            }
            return context.makeImage()
        }
    }
}
