//
//  JPEGMetadataTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("JPEG Metadata Tests")
struct JPEGMetadataTests {

    // MARK: - Stripping -

    @Test("Strips the segments that can carry personal data")
    func stripsPrivacySegments() {
        let jpeg = JPEG.build([
            .app(0xE1, payload: Array("Exif\0\0GPS 51.5N".utf8)),
            .app(0xEF, payload: Array("vendor-serial-1234".utf8)),
            .comment("shot at home"),
        ])

        let stripped = JPEGMetadata.stripped(jpeg)

        #expect(!stripped.contains(Data("GPS 51.5N".utf8)))
        #expect(!stripped.contains(Data("vendor-serial-1234".utf8)))
        #expect(!stripped.contains(Data("shot at home".utf8)))
        #expect(stripped == JPEG.build([]))
    }

    /// JFIF, ICC and Adobe carry no personal data, and dropping the colour ones
    /// visibly shifts a wide-gamut photo.
    @Test("Keeps the allowed segments verbatim while dropping the rest")
    func keepsAllowedSegmentsInterleaved() {
        let icc = Array("ICC_PROFILE\0colour-data".utf8)
        let jpeg = JPEG.build([
            .app(0xE0, payload: Array("JFIF\0".utf8)),
            .app(0xE1, payload: Array("Exif\0\0secret".utf8)),
            .comment("drop me"),
            .app(0xE2, payload: icc),
            .app(0xEE, payload: Array("Adobe".utf8)),
        ])

        let stripped = JPEGMetadata.stripped(jpeg)

        #expect(stripped == JPEG.build([
            .app(0xE0, payload: Array("JFIF\0".utf8)),
            .app(0xE2, payload: icc),
            .app(0xEE, payload: Array("Adobe".utf8)),
        ]))
    }

    /// Two APP1s is the common real-world shape: EXIF plus XMP.
    @Test("Strips every APP1, not just the first")
    func stripsMultipleAPP1Segments() {
        let jpeg = JPEG.build([
            .app(0xE1, payload: Array("Exif\0\0camera-serial".utf8)),
            .app(0xE1, payload: Array("http://ns.adobe.com/xap/1.0/\0creator".utf8)),
        ])

        let stripped = JPEGMetadata.stripped(jpeg)

        #expect(!stripped.contains(Data("camera-serial".utf8)))
        #expect(!stripped.contains(Data("creator".utf8)))
        #expect(stripped == JPEG.build([]))
    }

    /// A marker may be preceded by any number of 0xFF fill bytes; miscounting
    /// them would desynchronize the walker and splice the wrong range.
    @Test("Strips a segment introduced by fill bytes")
    func stripsPastFillBytes() {
        var jpeg = Data([0xFF, 0xD8])
        jpeg.append(contentsOf: [0xFF, 0xFF, 0xFF])
        jpeg.append(JPEG.segment(.comment("padded secret")))
        jpeg.append(contentsOf: JPEG.scanAndEnd)

        let stripped = JPEGMetadata.stripped(jpeg)

        #expect(!stripped.contains(Data("padded secret".utf8)))
    }

    /// RSTn and TEM carry no length, so treating them as length-prefixed would
    /// read the following bytes as a size and walk off the segment grid.
    @Test("Walks past standalone markers to reach a later segment")
    func stripsAfterStandaloneMarkers() {
        var jpeg = Data([0xFF, 0xD8])
        jpeg.append(contentsOf: [0xFF, 0x01])       // TEM
        jpeg.append(contentsOf: [0xFF, 0xD3])       // RST3
        jpeg.append(JPEG.segment(.comment("after standalones")))
        jpeg.append(contentsOf: JPEG.scanAndEnd)

        let stripped = JPEGMetadata.stripped(jpeg)

        #expect(!stripped.contains(Data("after standalones".utf8)))
    }

    // MARK: - Passthrough -

    @Test("Returns a clean JPEG untouched")
    func cleanJPEGIsUnchanged() {
        let jpeg = JPEG.build([.app(0xE0, payload: Array("JFIF\0".utf8))])

        #expect(JPEGMetadata.stripped(jpeg) == jpeg)
    }

    /// The decoder rejects a malformed stream on its own; a half-rewritten one
    /// would be worse.
    @Test("Returns a stream whose declared length overruns the data untouched")
    func truncatedSegmentIsUnchanged() {
        var jpeg = Data([0xFF, 0xD8])
        jpeg.append(contentsOf: [0xFF, 0xE1])
        // Declares 4KB of payload that isn't there.
        jpeg.append(contentsOf: [0x10, 0x00])
        jpeg.append(contentsOf: Array("Exif\0\0truncated".utf8))

        #expect(JPEGMetadata.stripped(jpeg) == jpeg)
    }

    @Test("Returns bytes that are not a JPEG untouched",
          arguments: [
              Data(),
              Data([0xFF]),
              Data(repeating: 0xAB, count: 512),
              Data([0x89, 0x50, 0x4E, 0x47]),   // PNG signature
          ])
    func nonJPEGIsUnchanged(input: Data) {
        #expect(JPEGMetadata.stripped(input) == input)
    }
}

// MARK: - Fixtures -

/// Builds minimal JPEG streams: SOI, the given segments, then an empty scan and
/// EOI. Enough for the marker walker without pulling in an image encoder.
private enum JPEG {

    enum Segment {
        case app(UInt8, payload: [UInt8])
        case comment(String)
    }

    static let scanAndEnd: [UInt8] = [0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9]

    static func build(_ segments: [Segment]) -> Data {
        var data = Data([0xFF, 0xD8])
        for segment in segments {
            data.append(self.segment(segment))
        }
        data.append(contentsOf: scanAndEnd)
        return data
    }

    static func segment(_ segment: Segment) -> Data {
        switch segment {
        case .app(let marker, let payload):
            encode(marker: marker, payload: payload)
        case .comment(let text):
            encode(marker: 0xFE, payload: Array(text.utf8))
        }
    }

    private static func encode(marker: UInt8, payload: [UInt8]) -> Data {
        let length = payload.count + 2
        var data = Data([0xFF, marker])
        data.append(contentsOf: [UInt8(length >> 8), UInt8(length & 0xFF)])
        data.append(contentsOf: payload)
        return data
    }
}
