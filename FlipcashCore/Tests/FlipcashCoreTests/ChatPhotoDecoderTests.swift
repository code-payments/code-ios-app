//
//  ChatPhotoDecoderTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FlipcashCore

@Suite("Chat photo decoder")
struct ChatPhotoDecoderTests {

    private static func jpeg(width: Int, height: Int, orientation: CGImagePropertyOrientation = .up) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("A sideways EXIF orientation is drawn into the pixels")
    func bakesOrientation() async throws {
        let decoded = try #require(await ChatPhotoDecoder.decode(Self.jpeg(width: 4, height: 3, orientation: .right)))

        #expect(decoded.width == 3)
        #expect(decoded.height == 4)
    }

    @Test("A cap on the longer edge downsamples, and never upsamples")
    func capsLongerEdge() async throws {
        let data = try Self.jpeg(width: 400, height: 200)

        let capped = try #require(await ChatPhotoDecoder.decode(data, maxPixelSize: 100))
        let uncapped = try #require(await ChatPhotoDecoder.decode(data, maxPixelSize: 4000))

        #expect(capped.width == 100)
        #expect(capped.height == 50)
        #expect(uncapped.width == 400)
    }

    @Test("Bytes that are not an image decode to nothing")
    func rejectsGarbage() async {
        #expect(await ChatPhotoDecoder.decode(Data([1, 2, 3])) == nil)
    }
}
