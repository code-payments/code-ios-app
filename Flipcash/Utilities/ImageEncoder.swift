//
//  ImageEncoder.swift
//  Flipcash
//

import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoderError: Error {
    case cannotEncode
    case cannotFitBudget
}

nonisolated enum ImageEncoder {

    /// Encodes `image` as JPEG data, guaranteeing the result is <= `maxBytes`.
    /// Progressively lowers quality and, if needed, downsizes the image until
    /// the budget is met. Throws if the image can't be encoded or won't fit.
    static func encodeForUpload(_ image: UIImage, maxBytes: Int) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try encodeForUploadSync(image, maxBytes: maxBytes)
        }.value
    }

    static func encodeForUploadSync(_ image: UIImage, maxBytes: Int) throws -> Data {
        let qualitySteps: [CGFloat] = [0.9, 0.7, 0.5, 0.3]
        for quality in qualitySteps {
            guard let data = jpegData(from: image, quality: quality) else {
                throw ImageEncoderError.cannotEncode
            }
            if data.count <= maxBytes { return data }
        }

        var current = image
        let dimensionSteps: [CGFloat] = [1024, 768, 512, 384, 256]
        for maxDim in dimensionSteps {
            current = ImageCompressor.compressSync(current, maxDimension: maxDim)
            for quality in qualitySteps {
                guard let data = jpegData(from: current, quality: quality) else {
                    throw ImageEncoderError.cannotEncode
                }
                if data.count <= maxBytes { return data }
            }
        }

        throw ImageEncoderError.cannotFitBudget
    }

    /// Encodes `image` as JPEG carrying no EXIF, GPS, or TIFF metadata.
    ///
    /// `UIImage.jpegData(compressionQuality:)` copies the source photo's
    /// metadata into the output, which the blob service refuses with
    /// `PRIVACY_METADATA` — and which would otherwise publish the capture
    /// location alongside the picture.
    static func jpegData(from image: UIImage, quality: CGFloat) -> Data? {
        // Writing a CGImage drops `imageOrientation`, so bake any rotation in
        // before encoding rather than recording it in the EXIF being stripped.
        let upright = image.imageOrientation == .up ? image : ImageCompressor.normalizedSync(image)

        guard let cgImage = upright.cgImage else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        // ImageIO writes an APP1 EXIF segment even when handed no metadata, and
        // the service allowlists segments rather than inspecting their contents.
        return strippingPrivacySegments(output as Data)
    }

    /// Removes the JPEG segments the blob service refuses: every APPn outside
    /// the JFIF, ICC and Adobe allowlist, plus free-form comments.
    ///
    /// Returns `jpeg` untouched when it doesn't parse — the decoder rejects a
    /// malformed stream on its own, and a half-rewritten one would be worse.
    static func strippingPrivacySegments(_ jpeg: Data) -> Data {
        let allowedAppMarkers: Set<UInt8> = [0xE0, 0xE2, 0xEE] // JFIF, ICC, Adobe
        let markerSOI: UInt8 = 0xD8
        let markerTEM: UInt8 = 0x01
        let markerSOS: UInt8 = 0xDA
        let markerEOI: UInt8 = 0xD9
        let markerCOM: UInt8 = 0xFE

        let bytes = [UInt8](jpeg)
        guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == markerSOI else {
            return jpeg
        }

        var output = Data([0xFF, markerSOI])
        var position = 2

        while position + 1 < bytes.count {
            guard bytes[position] == 0xFF else { return jpeg }

            let marker = bytes[position + 1]

            // A marker may be padded with any number of 0xFF fill bytes.
            if marker == 0xFF {
                position += 1
                continue
            }

            // Standalone markers, the RSTn restart markers included, carry no payload.
            if marker == markerSOI || marker == markerTEM || (0xD0...0xD7).contains(marker) {
                output.append(contentsOf: [0xFF, marker])
                position += 2
                continue
            }

            // Everything from the scan onwards is entropy-coded pixel data.
            if marker == markerSOS || marker == markerEOI {
                output.append(contentsOf: bytes[position...])
                return output
            }

            guard position + 4 <= bytes.count else { return jpeg }

            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            guard length >= 2, position + 2 + length <= bytes.count else { return jpeg }

            let carriesPersonalData = marker == markerCOM
                || ((0xE0...0xEF).contains(marker) && !allowedAppMarkers.contains(marker))

            if !carriesPersonalData {
                output.append(contentsOf: bytes[position..<(position + 2 + length)])
            }

            position += 2 + length
        }

        return output
    }
}
