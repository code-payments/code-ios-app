//
//  ComposerChip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import Observation
import FlipcashCore

/// Whether a failed chip can be uploaded again, or the server refused its bytes for good.
enum ChatMediaChipFailure: Equatable {
    case notRetryable
    case retryable
}

/// A photo staged in the composer, and how far its upload has got.
///
/// A reference type so the send path can hold the chip it was handed and await its upload later;
/// a chip lives only as long as the composer, never in the persisted draft.
@MainActor
@Observable
final class ComposerChip: Identifiable {

    enum State: Equatable {
        case preparing
        case uploading
        case uploaded(BlobID)
        case failed(ChatMediaChipFailure)
    }

    let id = UUID()
    let image: UIImage
    var state: State = .preparing

    /// Pixel width of the image as it will be uploaded, known before the upload starts.
    var preparedWidth: Int?

    /// Pixel height of the image as it will be uploaded, known before the upload starts.
    var preparedHeight: Int?

    /// The upload in flight or finished for this chip, which the send path awaits rather than
    /// starting its own.
    @ObservationIgnored var uploadTask: Task<BlobID, Error>?

    /// The uploader the last attempt went through, kept so a failed send can upload again after the
    /// composer has let go of the chip.
    @ObservationIgnored private var uploader: ChatMediaUploader?

    init(image: UIImage) {
        self.image = image
    }

    /// Uploads the image through `uploader`, replacing any earlier attempt; calling it again after
    /// a retryable failure is how the chip is retried.
    func startUpload(using uploader: ChatMediaUploader) {
        self.uploader = uploader
        uploadTask?.cancel()
        state = .preparing

        uploadTask = Task {
            do {
                let blobID = try await uploader.upload(image) { width, height in
                    preparedWidth = width
                    preparedHeight = height
                    state = .uploading
                }
                if !Task.isCancelled {
                    state = .uploaded(blobID)
                }
                return blobID
            } catch let error as ChatMediaUploadError {
                if !Task.isCancelled {
                    state = .failed(error.isRetryable ? .retryable : .notRetryable)
                }
                throw error
            }
        }
    }

    /// Uploads again through the uploader the last attempt used, returning `false` when no upload
    /// was ever started.
    @discardableResult
    func retryUpload() -> Bool {
        guard let uploader else { return false }
        startUpload(using: uploader)
        return true
    }
}
