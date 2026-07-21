//
//  ImageEncoder.swift
//  Flipcash
//

import UIKit
import ImageIO
import UniformTypeIdentifiers
import FlipcashCore

enum ImageEncoderError: Error, Equatable {
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
            if let data = try encoded(image, quality: quality, maxBytes: maxBytes) { return data }
        }

        var current = image
        let dimensionSteps: [CGFloat] = [1024, 768, 512, 384, 256]
        for maxDim in dimensionSteps {
            current = ImageCompressor.compressSync(current, maxDimension: maxDim)
            for quality in qualitySteps {
                if let data = try encoded(current, quality: quality, maxBytes: maxBytes) { return data }
            }
        }

        throw ImageEncoderError.cannotFitBudget
    }

    /// Returns the encoded image when it fits `maxBytes`, or nil to try the next
    /// step down.
    ///
    /// Strips here too, not only in the uploader: the currency icon ships inside
    /// the Launch RPC and never passes through blob storage. Stripping only
    /// removes bytes, so the budget is checked before it.
    private static func encoded(_ image: UIImage, quality: CGFloat, maxBytes: Int) throws -> Data? {
        guard let data = jpegData(from: image, quality: quality) else {
            throw ImageEncoderError.cannotEncode
        }

        guard data.count <= maxBytes else { return nil }

        return JPEGMetadata.stripped(data)
    }

    /// Encodes `image` as JPEG carrying no EXIF, GPS, or TIFF metadata.
    ///
    /// `UIImage.jpegData(compressionQuality:)` copies the source photo's
    /// metadata into the output, which the blob service refuses with
    /// `PRIVACY_METADATA` — and which would otherwise publish the capture
    /// location alongside the picture.
    private static func jpegData(from image: UIImage, quality: CGFloat) -> Data? {
        // Writing a CGImage drops `imageOrientation`, so bake any rotation in
        // before encoding rather than recording it in the EXIF being stripped.
        let upright = ImageCompressor.normalizedSync(image)

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

        return output as Data
    }

}
