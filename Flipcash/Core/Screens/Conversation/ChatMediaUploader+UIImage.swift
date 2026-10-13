//
//  ChatMediaUploader+UIImage.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import ImageIO
import FlipcashCore

extension ChatMediaUploader {

    /// Returns the finalized photo for `image`, throwing `ChatMediaUploadError`; see
    /// ``upload(_:orientation:progress:onStored:onPrepared:onEncoded:)``.
    func upload(
        _ image: UIImage,
        progress: (any ChatPhotoUploadProgress)? = nil,
        onStored: (UploadedPhoto) -> Void = { _ in },
        onPrepared: (Int, Int) -> Void,
        onEncoded: (Data) -> Void = { _ in }
    ) async throws -> UploadedPhoto {
        guard let cgImage = image.cgImage else {
            throw ChatMediaUploadError.encodingFailed(.encodingFailed)
        }
        return try await upload(
            cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            progress: progress,
            onStored: onStored,
            onPrepared: onPrepared,
            onEncoded: onEncoded
        )
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:               self = .up
        case .upMirrored:       self = .upMirrored
        case .down:             self = .down
        case .downMirrored:     self = .downMirrored
        case .left:             self = .left
        case .leftMirrored:     self = .leftMirrored
        case .right:            self = .right
        case .rightMirrored:    self = .rightMirrored
        @unknown default:       self = .up
        }
    }
}
