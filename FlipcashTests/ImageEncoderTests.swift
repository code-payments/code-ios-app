//
//  ImageEncoderTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@Suite("ImageEncoder")
struct ImageEncoderTests {

    @Test("encode returns data within byte budget for a simple image")
    func encode_simpleImage_withinBudget() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 500, height: 500))
        }

        let data = try await ImageEncoder.encodeForUpload(image, maxBytes: 1_048_576)

        #expect(data.count <= 1_048_576)
        #expect(UIImage(data: data) != nil)
    }

    @Test("encode downsizes a large image to stay under budget")
    func encode_largeImage_downsizesUnderBudget() async throws {
        let image = try makeNoiseImage(side: 2560)

        // 0.3 mirrors the encoder's lowest full-size quality step: when even
        // that encode exceeds the budget, encodeForUpload can't satisfy
        // maxBytes without downsizing. Guards against a fixture too cheap to
        // exercise the downsize path.
        let smallestFullSizeEncode = try #require(image.jpegData(compressionQuality: 0.3))
        #expect(smallestFullSizeEncode.count > 1_048_576)

        let data = try await ImageEncoder.encodeForUpload(image, maxBytes: 1_048_576)

        #expect(data.count <= 1_048_576)
        #expect(UIImage(data: data) != nil)
    }

    /// Deterministic per-pixel noise built directly from a pixel buffer.
    /// Noise defeats JPEG compression, so a modest canvas encodes well over
    /// the upload budget — and skipping CoreGraphics drawing keeps the
    /// fixture cheap under Thread Sanitizer, which the test scheme enables.
    private func makeNoiseImage(side: Int) throws -> UIImage {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        var words = [UInt64](repeating: 0, count: side * side * 4 / 8)
        for i in words.indices {
            words[i] = next()
        }

        let data = words.withUnsafeBytes { Data($0) }
        let provider = try #require(CGDataProvider(data: data as CFData))
        let cgImage = try #require(CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            // RGBX — .noneSkipLast ignores the random fourth byte.
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return UIImage(cgImage: cgImage)
    }
}
