//
//  ImageCompressorTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@Suite("ImageCompressor")
struct ImageCompressorTests {

    // MARK: - Passthrough

    @Test("Returns original image when within max dimension")
    func smallImage_passesThrough() {
        let image = makeImage(size: CGSize(width: 500, height: 500))
        let result = ImageCompressor.compress(image)

        #expect(result.size.width == 500)
        #expect(result.size.height == 500)
    }

    @Test("Returns original image when exactly at max dimension")
    func exactLimit_passesThrough() {
        let image = makeImage(size: CGSize(width: 1024, height: 768))
        let result = ImageCompressor.compress(image)

        #expect(result.size.width == 1024)
        #expect(result.size.height == 768)
    }

    // MARK: - Downscaling

    @Test("Downscales preserving aspect ratio", arguments: [
        (input: CGSize(width: 4000, height: 2000), expected: CGSize(width: 1024, height: 512)),
        (input: CGSize(width: 1500, height: 3000), expected: CGSize(width: 512, height: 1024)),
        (input: CGSize(width: 2048, height: 2048), expected: CGSize(width: 1024, height: 1024)),
    ] as [(input: CGSize, expected: CGSize)])
    func downscalesCorrectly(input: CGSize, expected: CGSize) {
        let image = makeImage(size: input)
        let result = ImageCompressor.compress(image)

        #expect(Int(result.size.width) == Int(expected.width))
        #expect(Int(result.size.height) == Int(expected.height))
    }

    // MARK: - Custom max dimension

    @Test("Respects custom max dimension")
    func customMaxDimension() {
        let image = makeImage(size: CGSize(width: 1000, height: 500))
        let result = ImageCompressor.compress(image, maxDimension: 200)

        #expect(result.size.width == 200)
        #expect(result.size.height == 100)
    }

    // MARK: - Orientation normalization

    @Test("Normalizes rotated image to orientation up")
    func rotatedImage_normalizedToUp() throws {
        let ciImage = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 500, height: 500))
        let cgImage = try #require(CIContext().createCGImage(ciImage, from: ciImage.extent))
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        #expect(rotated.imageOrientation == .right)

        let result = ImageCompressor.compress(rotated)

        #expect(result.imageOrientation == .up)
    }

    // MARK: - Helpers

    private func makeImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
    }
}
