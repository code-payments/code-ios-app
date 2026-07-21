//
//  JPEGMetadata.swift
//  FlipcashCore
//

import Foundation

public enum JPEGMetadata {

    /// The APPn segments a stripped JPEG may keep: JFIF, the ICC colour
    /// profile, and Adobe's colour transform. None carries personal data, and
    /// dropping the colour ones visibly shifts a wide-gamut photo.
    private static let allowedAppMarkers: Set<UInt8> = [0xE0, 0xE2, 0xEE]

    private static let markerSOI: UInt8 = 0xD8
    private static let markerTEM: UInt8 = 0x01
    private static let markerSOS: UInt8 = 0xDA
    private static let markerEOI: UInt8 = 0xD9
    private static let markerCOM: UInt8 = 0xFE

    /// Returns `jpeg` without the segments that can carry personal data — every
    /// APPn outside the allowlist, plus free-form comments.
    ///
    /// Returns the input untouched when it carries none, and when it doesn't
    /// parse: the decoder rejects a malformed stream on its own, and a
    /// half-rewritten one would be worse.
    ///
    /// Rotation must already be baked into the pixels, since stripping EXIF
    /// discards the orientation tag that decoders rely on.
    public static func stripped(_ jpeg: Data) -> Data {
        let bytes = [UInt8](jpeg)

        guard let segments = privacySegments(in: bytes), !segments.isEmpty else {
            return jpeg
        }

        var output = Data()
        output.reserveCapacity(jpeg.count)

        var copiedUpTo = 0
        for segment in segments {
            output.append(contentsOf: bytes[copiedUpTo..<segment.lowerBound])
            copiedUpTo = segment.upperBound
        }
        output.append(contentsOf: bytes[copiedUpTo...])

        return output
    }

    /// Walks the marker segments and returns the byte ranges to drop, or nil
    /// when the stream doesn't parse. Stops at the scan — everything past it is
    /// entropy-coded pixel data.
    private static func privacySegments(in bytes: [UInt8]) -> [Range<Int>]? {
        guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == markerSOI else {
            return nil
        }

        var segments: [Range<Int>] = []
        var position = 2

        while position + 1 < bytes.count {
            guard bytes[position] == 0xFF else { return nil }

            let marker = bytes[position + 1]

            // A marker may be padded with any number of 0xFF fill bytes.
            if marker == 0xFF {
                position += 1
                continue
            }

            // Standalone markers, the RSTn restart markers included, carry no payload.
            if marker == markerSOI || marker == markerTEM || (0xD0...0xD7).contains(marker) {
                position += 2
                continue
            }

            if marker == markerSOS || marker == markerEOI {
                return segments
            }

            guard position + 4 <= bytes.count else { return nil }

            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            guard length >= 2, position + 2 + length <= bytes.count else { return nil }

            let carriesPersonalData = marker == markerCOM
                || ((0xE0...0xEF).contains(marker) && !allowedAppMarkers.contains(marker))

            if carriesPersonalData {
                segments.append(position..<(position + 2 + length))
            }

            position += 2 + length
        }

        return segments
    }
}
