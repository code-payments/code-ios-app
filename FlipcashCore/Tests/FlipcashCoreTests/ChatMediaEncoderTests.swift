//
//  ChatMediaEncoderTests.swift
//  FlipcashCoreTests
//

import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import FlipcashCore

@Suite("Chat media encoder")
struct ChatMediaEncoderTests {

    // MARK: - Quality ladder -

    @Test("Walks the ladder highest first and stops at the first quality that fits")
    func stopsAtFirstFit() throws {
        let attempts = Mutex<[Double]>([])
        let encoder = ChatMediaEncoder { _, quality in
            attempts.withLock { $0.append(quality) }
            return Data(count: quality > 0.75 ? 200 : 100)
        }

        let data = try encoder.encode(Self.image(width: 4, height: 4), target: .init(width: 4, height: 4), maxSizeBytes: 100)

        #expect(data.count == 100)
        #expect(attempts.withLock { $0 } == [0.9, 0.8, 0.7])
    }

    @Test("Throws tooLarge when no quality on the ladder fits")
    func givesUpAfterLastStep() throws {
        let attempts = Mutex<[Double]>([])
        let encoder = ChatMediaEncoder { _, quality in
            attempts.withLock { $0.append(quality) }
            return Data(count: 200)
        }

        #expect(throws: ChatMediaEncoder.Error.tooLarge) {
            try encoder.encode(Self.image(width: 4, height: 4), target: .init(width: 4, height: 4), maxSizeBytes: 100)
        }
        #expect(attempts.withLock { $0 } == ChatMediaEncoder.qualityLadder)
    }

    @Test("Throws encodingFailed when no quality encodes at all")
    func encodeFailure() throws {
        let encoder = ChatMediaEncoder { _, _ in nil }

        #expect(throws: ChatMediaEncoder.Error.encodingFailed) {
            try encoder.encode(Self.image(width: 4, height: 4), target: .init(width: 4, height: 4), maxSizeBytes: 100)
        }
    }

    /// The reservation signs the stripped bytes, so a JPEG that fits only once
    /// its EXIF is gone must be accepted — and handed back stripped.
    @Test("Measures the size after stripping metadata")
    func measuresStrippedSize() throws {
        let exif = Data([0xFF, 0xE1, 0x00, 0x0A] + Array("Exif\0\0GPS".utf8).prefix(8))
        let bare = Data([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x11, 0xFF, 0xD9])
        let withExif = bare.prefix(2) + exif + bare.dropFirst(2)
        let encoder = ChatMediaEncoder { _, _ in withExif }

        let data = try encoder.encode(Self.image(width: 4, height: 4), target: .init(width: 4, height: 4), maxSizeBytes: bare.count)

        #expect(data == bare)
    }

    // MARK: - Real encode -

    @Test("Encodes a real JPEG at the target size")
    func encodesAtTarget() throws {
        let data = try ChatMediaEncoder().encode(
            Self.image(width: 40, height: 20),
            target: .init(width: 20, height: 10),
            maxSizeBytes: 1_000_000
        )

        let (width, height) = try Self.pixelSize(of: data)
        #expect(width == 20)
        #expect(height == 10)
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    /// A portrait capture arrives as landscape pixels tagged `.right`; the
    /// target is in display space, and the output must decode upright without
    /// an orientation tag.
    @Test("Bakes a sideways orientation into upright pixels")
    func bakesOrientation() throws {
        let data = try ChatMediaEncoder().encode(
            Self.image(width: 40, height: 20),
            orientation: .right,
            target: .init(width: 10, height: 20),
            maxSizeBytes: 1_000_000
        )

        let (width, height) = try Self.pixelSize(of: data)
        #expect(width == 10)
        #expect(height == 20)

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32
        #expect(orientation == nil || orientation == CGImagePropertyOrientation.up.rawValue)
    }

    /// `.right` stores the displayed top along the pixels' left edge, so a
    /// source red on its left half must display red on top.
    @Test("Rotates a .right capture the way a viewer displays it")
    func rotatesInDisplayDirection() throws {
        let data = try ChatMediaEncoder().encode(
            Self.image(width: 40, height: 20, leftHalf: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            orientation: .right,
            target: .init(width: 10, height: 20),
            maxSizeBytes: 1_000_000
        )

        let top = try Self.pixel(of: data, x: 5, y: 2)
        let bottom = try Self.pixel(of: data, x: 5, y: 17)
        #expect(top.red > 200 && top.blue < 60)
        #expect(bottom.blue > 200 && bottom.red < 60)
    }

    // MARK: - Fixtures -

    private static func image(width: Int, height: Int, leftHalf: CGColor? = nil) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let leftHalf {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(leftHalf)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
        return try #require(context.makeImage())
    }

    /// Returns the decoded RGB at `(x, y)`, with `y` counted from the top.
    private static func pixel(of data: Data, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &buffer,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2])
    }

    private static func pixelSize(of data: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }
}
