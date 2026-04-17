//
//  ImageCompressorTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@Suite("ImageCompressor")
struct ImageCompressorTests {

    @Test("Returns the same image instance when within max dimension", arguments: [
        CGSize(width: 500, height: 500),
        CGSize(width: 1024, height: 768),
        CGSize(width: 1024, height: 1024),
        CGSize(width: 800, height: 1024),
    ])
    func withinBounds_passesThroughIdentically(size: CGSize) {
        let image = makeImage(size: size)
        let result = ImageCompressor.compressSync(image)

        #expect(result === image)
    }

    @Test("Downscales preserving aspect ratio", arguments: [
        (input: CGSize(width: 4000, height: 2000), expected: CGSize(width: 1024, height: 512)),
        (input: CGSize(width: 1500, height: 3000), expected: CGSize(width: 512, height: 1024)),
        (input: CGSize(width: 2048, height: 2048), expected: CGSize(width: 1024, height: 1024)),
    ] as [(input: CGSize, expected: CGSize)])
    func downscalesCorrectly(input: CGSize, expected: CGSize) {
        let image = makeImage(size: input)
        let result = ImageCompressor.compressSync(image)

        #expect(result.size.width == expected.width)
        #expect(result.size.height == expected.height)
    }

    @Test("Respects custom max dimension")
    func customMaxDimension() {
        let image = makeImage(size: CGSize(width: 1000, height: 500))
        let result = ImageCompressor.compressSync(image, maxDimension: 200)

        #expect(result.size.width == 200)
        #expect(result.size.height == 100)
    }

    @Test("Normalizes rotated image to orientation up")
    func rotatedImage_normalizedToUp() throws {
        let rotated = try makeRotatedImage(size: CGSize(width: 500, height: 500), orientation: .right)
        #expect(rotated.imageOrientation == .right)

        let result = ImageCompressor.compressSync(rotated)

        #expect(result.imageOrientation == .up)
    }

    @Test("Rotated oversized image is both normalized and downscaled")
    func rotatedOversized_normalizedAndDownscaled() throws {
        // CGImage is 2000x1000, but .right orientation swaps display dims
        // — UIImage.size reports (1000, 2000). After normalize+downscale,
        // the longest side caps to 1024 → result is 512x1024.
        let rotated = try makeRotatedImage(size: CGSize(width: 2000, height: 1000), orientation: .right)

        let result = ImageCompressor.compressSync(rotated)

        #expect(result.imageOrientation == .up)
        #expect(result.size.width == 512)
        #expect(result.size.height == 1024)
    }

    private func makeImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
    }

    private func makeRotatedImage(size: CGSize, orientation: UIImage.Orientation) throws -> UIImage {
        let ciImage = CIImage(color: .red).cropped(to: CGRect(origin: .zero, size: size))
        let cgImage = try #require(CIContext().createCGImage(ciImage, from: ciImage.extent))
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
