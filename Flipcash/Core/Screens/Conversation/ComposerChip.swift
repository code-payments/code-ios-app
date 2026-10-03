//
//  ComposerChip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import Observation
import FlipcashCore
import FlipcashUI

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
    /// A display-ready copy decoded ahead of staging, so the chip can draw on its first frame — the
    /// camera's capture shrinks into the chip before its own thumbnail could be decoded.
    let preview: UIImage?
    var state: State = .preparing

    /// How far this photo's send has got, which its transcript bubble draws.
    let progress = ChatPhotoSendProgress()

    /// Pixel width of the image as it will be uploaded, known before the upload starts.
    var preparedWidth: Int?

    /// Pixel height of the image as it will be uploaded, known before the upload starts.
    var preparedHeight: Int?

    /// The upload in flight or finished for this chip, which the send path awaits rather than
    /// starting its own.
    @ObservationIgnored var uploadTask: Task<UploadedPhoto, Error>?

    /// The uploader the last attempt went through, kept so a failed send can upload again after the
    /// composer has let go of the chip.
    @ObservationIgnored private var uploader: ChatMediaUploader?

    /// The photo whose bytes storage already holds, so a retry waits on the server again instead of
    /// storing a second copy. Nil until a store succeeds, and again once the server rejects it.
    @ObservationIgnored private var stored: UploadedPhoto?

    /// The JPEG the upload encoded, kept so a retry stores the same bytes instead of encoding again.
    @ObservationIgnored private var encoded: Data?

    /// Hears the encoded JPEG as soon as it exists; see ``persist(onEncoded:onStored:)``.
    @ObservationIgnored private var onEncoded: ((Data) -> Void)?

    /// Hears the stored photo as soon as its bytes land; see ``persist(onEncoded:onStored:)``.
    @ObservationIgnored private var onStored: ((UploadedPhoto) -> Void)?

    init(image: UIImage, preview: UIImage? = nil) {
        self.image = image
        self.preview = preview
    }

    /// Hands the encoded JPEG and the stored photo to the callbacks, now if the chip already has
    /// them and otherwise when they arrive, so a send can keep them on disk.
    func persist(onEncoded: @escaping (Data) -> Void, onStored: @escaping (UploadedPhoto) -> Void) {
        self.onEncoded = onEncoded
        self.onStored = onStored
        if let encoded { onEncoded(encoded) }
        if let stored { onStored(stored) }
    }

    /// Rebuilds a chip for a send read back from disk: `encoded` is the JPEG that was held and
    /// `stored` the photo whose bytes had landed, if they had. With nothing stored the chip starts
    /// failed and retryable; otherwise ``startUpload(using:)`` resumes by waiting on the server.
    func restore(encoded: Data, stored: UploadedPhoto?, uploader: ChatMediaUploader) {
        self.encoded = encoded
        self.stored = stored
        self.uploader = uploader
        if stored == nil {
            state = .failed(.retryable)
            progress.fail()
        }
    }

    /// Uploads the image through `uploader`, replacing any earlier attempt; calling it again after
    /// a retryable failure is how the chip is retried.
    func startUpload(using uploader: ChatMediaUploader) {
        self.uploader = uploader
        uploadTask?.cancel()
        state = .preparing
        progress.beginAttempt()

        uploadTask = Task {
            do {
                let photo: UploadedPhoto
                if let stored {
                    state = .uploading
                    photo = try await uploader.finalize(stored, progress: progress)
                } else if let encoded {
                    photo = try await uploader.upload(jpeg: encoded, progress: progress, onStored: { photo in
                        stored = photo
                        onStored?(photo)
                    }, onPrepared: { width, height in
                        preparedWidth = width
                        preparedHeight = height
                        state = .uploading
                    })
                } else {
                    photo = try await uploader.upload(image, progress: progress, onStored: { photo in
                        stored = photo
                        onStored?(photo)
                    }, onPrepared: { width, height in
                        preparedWidth = width
                        preparedHeight = height
                        state = .uploading
                    }, onEncoded: { data in
                        encoded = data
                        onEncoded?(data)
                    })
                }
                if !Task.isCancelled {
                    state = .uploaded(photo.blobID)
                }
                return photo
            } catch let error as ChatMediaUploadError {
                if case .rejected = error {
                    stored = nil
                }
                if !Task.isCancelled {
                    state = .failed(error.isRetryable ? .retryable : .notRetryable)
                    progress.fail()
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
