//
//  ImageEncoder.swift
//  Flipcash
//

import UIKit

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
            guard let data = image.jpegData(compressionQuality: quality) else {
                throw ImageEncoderError.cannotEncode
            }
            if data.count <= maxBytes { return data }
        }

        var current = image
        let dimensionSteps: [CGFloat] = [1024, 768, 512, 384, 256]
        for maxDim in dimensionSteps {
            current = ImageCompressor.compressSync(current, maxDimension: maxDim)
            for quality in qualitySteps {
                guard let data = current.jpegData(compressionQuality: quality) else {
                    throw ImageEncoderError.cannotEncode
                }
                if data.count <= maxBytes { return data }
            }
        }

        throw ImageEncoderError.cannotFitBudget
    }
}
