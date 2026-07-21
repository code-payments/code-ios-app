//
//  ImageEncoderTests.swift
//  FlipcashTests
//

import Testing
import UIKit
import ImageIO
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

    /// The blob service refuses an upload carrying privacy metadata
    /// (`REJECTION_REASON_PRIVACY_METADATA`), so a JPEG that keeps the source
    /// photo's EXIF fails every profile-picture upload — and leaks the capture
    /// location on every currency icon. `UIImage.jpegData` copies it through;
    /// the encoder must not.
    @Test("encode strips EXIF, GPS and TIFF metadata")
    func encode_stripsPrivacyMetadata() async throws {
        let image = try makeImageCarryingMetadata()

        // The fixture has to actually carry metadata, or this proves nothing.
        let viaUIKit = try #require(image.jpegData(compressionQuality: 0.9))
        let uikitProperties = try #require(properties(of: viaUIKit))
        #expect(uikitProperties[kCGImagePropertyExifDictionary as String] != nil)

        let data = try await ImageEncoder.encodeForUpload(image, maxBytes: 1_048_576)
        let encoded = try #require(properties(of: data))

        // The service allowlists JPEG segments structurally rather than
        // reading their contents, so the contract is "no APP1 at all" — not
        // "an APP1 with nothing sensitive in it".
        let markers = appMarkers(in: data)
        #expect(!markers.contains(0xE1), "APP1 (EXIF/XMP) must not survive")
        #expect(!markers.contains(0xED), "APP13 (IPTC) must not survive")
        #expect(!markers.contains(0xFE), "COM comments must not survive")
        #expect(markers.allSatisfy { [0xE0, 0xE2, 0xEE].contains($0) })

        #expect(UIImage(data: data) != nil)
    }

    /// Walks the JPEG's marker segments and returns every APPn and COM marker
    /// it carries, mirroring how the service inspects an upload.
    private func appMarkers(in jpeg: Data) -> [UInt8] {
        let bytes = [UInt8](jpeg)
        guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return [] }

        var markers: [UInt8] = []
        var position = 2

        while position + 3 < bytes.count {
            guard bytes[position] == 0xFF else { break }
            let marker = bytes[position + 1]

            if marker == 0xFF { position += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                position += 2
                continue
            }
            if marker == 0xDA || marker == 0xD9 { break }

            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            guard length >= 2 else { break }

            if marker == 0xFE || (0xE0...0xEF).contains(marker) {
                markers.append(marker)
            }
            position += 2 + length
        }

        return markers
    }

    private func properties(of data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }

    /// Builds a JPEG carrying EXIF and GPS, then reads it back as a `UIImage`
    /// the way a photo picked from the library arrives.
    private func makeImageCarryingMetadata() throws -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let plain = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try #require(plain.cgImage), [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "captured"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5,
                kCGImagePropertyGPSLongitude: 0.12,
            ],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        return try #require(UIImage(data: output as Data))
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
