//
//  ChatMediaUploader.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import ImageIO
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.chat-media-upload")

/// The blob calls a chat photo upload makes, in the order it makes them.
///
/// The owner is bound by the conformer, so the upload never handles keys.
protocol ChatMediaBlobStoring {

    /// Returns the upload constraints in force for the owner.
    func uploadPolicy() async throws -> UploadPolicy

    /// Stores `data` and returns its blob, before the server has finalized it. `onProgress` hears
    /// the bytes going out, from any thread.
    func storeBlob(_ data: Data, mimeType: String, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> BlobID

    /// Stores `image` end-to-end encrypted with `seal` for its DM and returns the blob, before the
    /// server has finalized it. `onProgress` hears the sealed bytes going out, from any thread.
    func storeEncryptedBlob(_ image: Data, seal: ChatSeal, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> EncryptedBlobUpload

    /// Returns once the blob is servable, throwing `ErrorBlob.rejected` when it is refused and
    /// `ErrorBlob.timedOut` when it is still processing.
    func awaitBlobFinalization(blobID: BlobID) async throws
}

/// Stores chat photos on behalf of the signed-in owner.
struct SessionChatMediaBlobStore: ChatMediaBlobStoring {

    let session: Session
    let flipClient: FlipClient

    func uploadPolicy() async throws -> UploadPolicy {
        try await flipClient.uploadPolicy(owner: session.ownerKeyPair)
    }

    func storeBlob(_ data: Data, mimeType: String, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair, onProgress: onProgress)
    }

    func storeEncryptedBlob(_ image: Data, seal: ChatSeal, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> EncryptedBlobUpload {
        try await flipClient.storeEncryptedBlob(image, seal: seal, owner: session.ownerKeyPair, onProgress: onProgress)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }
}

/// A chat photo uploaded and finalized, in the form its message references it.
enum UploadedPhoto: Hashable, Sendable, Codable {
    /// A plaintext blob, whose metadata the server derives.
    case plain(BlobID)
    /// A blob end-to-end encrypted for the chat, with the metadata its sealed message carries.
    case sealed(SealedPhoto)

    /// The finalized blob.
    var blobID: BlobID {
        switch self {
        case .plain(let blobID):  blobID
        case .sealed(let photo):  photo.blobID
        }
    }
}

/// Why a chat photo did not upload.
enum ChatMediaUploadError: Error {
    /// The upload policy accepts no JPEG.
    case noMatchingConstraint
    /// The upload policy allows the owner no end-to-end encrypted upload.
    case encryptionNotAllowed
    /// The chat's seal could not be built, so the photo cannot be encrypted for it.
    case sealUnavailable(Error)
    /// The photo could not be encoded within the policy's size ceiling.
    case encodingFailed(ChatMediaEncoder.Error)
    /// The server refused the stored bytes.
    case rejected(BlobRejectionReason)
    /// The upload failed for a reason other than the bytes themselves, after any automatic retries.
    case failed(Error)

    /// Whether the send can never succeed, so nothing about it is worth keeping: the server refused
    /// the bytes, or the photo can't be uploaded again.
    var isTerminal: Bool {
        switch self {
        case .rejected:
            true
        case .noMatchingConstraint, .encryptionNotAllowed, .sealUnavailable, .encodingFailed, .failed:
            !isRetryable
        }
    }

    /// Whether uploading the same photo again could succeed.
    var isRetryable: Bool {
        switch self {
        case .noMatchingConstraint, .encryptionNotAllowed, .encodingFailed:
            false
        case .sealUnavailable(let error):
            // A peer key that couldn't be fetched may arrive, as may a chat lost to the network
            // (transport failures classify as suppressed); one shared-core refuses never will.
            error is PeerKeyUnavailable || (error as? ServerError)?.reportingLevel == .suppressed
        case .rejected(let reason):
            switch reason {
            case .moderation:
                false
            case .unsupportedType, .mismatchedType, .tooLarge, .corrupt, .privacyMetadata, .internal, .unknown, .unrecognized:
                true
            }
        case .failed:
            true
        }
    }
}

extension ChatMediaUploadError: ServerError {
    var reportingLevel: ErrorReportingLevel {
        switch self {
        case .noMatchingConstraint, .encryptionNotAllowed, .encodingFailed:
            .error
        case .sealUnavailable(let error):
            error is PeerKeyUnavailable ? .info : (error as? ServerError)?.reportingLevel ?? .error
        case .rejected:
            .info
        case .failed(let error):
            (error as? ServerError)?.reportingLevel ?? .error
        }
    }
}

/// Turns a staged photo into a finalized blob: downscaled to the upload policy's bounds, encoded
/// down the JPEG quality ladder, stored, and awaited until the server has finalized it. In a chat
/// that encrypts, the bytes are encrypted for it before they leave the device.
struct ChatMediaUploader {

    /// The seal to encrypt a photo with, or nil when the chat takes plaintext photos.
    typealias SealProvider = @MainActor () async throws -> ChatSeal?

    let blob: any ChatMediaBlobStoring

    /// Decides at upload time whether the photo is encrypted, the same decision text sends make.
    var seal: SealProvider = { nil }

    /// The wait before each automatic retry of a store that failed in transit; one entry per retry.
    var backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

    /// Returns the finalized photo for `image`, throwing `ChatMediaUploadError`.
    ///
    /// `onPrepared` receives the uploaded pixel width and height once, before any bytes are stored.
    /// `onEncoded` receives the JPEG that will be stored, before it is, so the caller can keep the
    /// exact bytes. `onStored` receives the photo once its bytes are stored, before the server has
    /// finalized it, so a failed wait can resume through ``finalize(_:progress:)`` instead of
    /// storing again. `progress`, when given, follows each store attempt's bytes and then the
    /// server's processing.
    func upload(
        _ image: UIImage,
        progress: ChatPhotoSendProgress? = nil,
        onStored: (UploadedPhoto) -> Void = { _ in },
        onPrepared: (Int, Int) -> Void,
        onEncoded: (Data) -> Void = { _ in }
    ) async throws -> UploadedPhoto {
        let (chatSeal, bounds, maxSizeBytes) = try await resolveConstraints()
        guard let cgImage = image.cgImage, maxSizeBytes > 0 else {
            throw ChatMediaUploadError.encodingFailed(.encodingFailed)
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let isSideways: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            isSideways = true
        case .up, .upMirrored, .down, .downMirrored:
            isSideways = false
        }

        let target = ChatMediaDownscale.target(
            sourceWidth: isSideways ? cgImage.height : cgImage.width,
            sourceHeight: isSideways ? cgImage.width : cgImage.height,
            maxWidth: bounds?.maxWidth ?? 0,
            maxHeight: bounds?.maxHeight ?? 0,
            maxPixels: bounds?.maxPixels ?? 0
        )
        onPrepared(target.width, target.height)

        let data: Data
        do {
            data = try await Self.encode(cgImage, orientation: orientation, target: target, maxSizeBytes: maxSizeBytes)
        } catch let error as ChatMediaEncoder.Error {
            throw ChatMediaUploadError.encodingFailed(error)
        }
        onEncoded(data)

        return try await storeAndFinalize(data, width: target.width, height: target.height, chatSeal: chatSeal, progress: progress, onStored: onStored)
    }

    /// Returns the finalized photo for `jpeg`, bytes an earlier ``upload(_:progress:onStored:onPrepared:onEncoded:)``
    /// produced, stored as they are rather than encoded again; throws `ChatMediaUploadError`.
    func upload(
        jpeg: Data,
        progress: ChatPhotoSendProgress? = nil,
        onStored: (UploadedPhoto) -> Void = { _ in },
        onPrepared: (Int, Int) -> Void
    ) async throws -> UploadedPhoto {
        let (chatSeal, _, _) = try await resolveConstraints()
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ChatMediaUploadError.encodingFailed(.encodingFailed)
        }
        onPrepared(width, height)
        return try await storeAndFinalize(jpeg, width: width, height: height, chatSeal: chatSeal, progress: progress, onStored: onStored)
    }

    /// The seal for this photo and the policy's bounds and size ceiling for the form it goes out in.
    private func resolveConstraints() async throws -> (ChatSeal?, UploadPolicy.ImageConstraints?, Int) {
        let chatSeal: ChatSeal?
        do {
            chatSeal = try await seal()
        } catch {
            try Task.checkCancellation()
            logger.info("No seal for chat photo", metadata: ["error": "\(error)"])
            throw ChatMediaUploadError.sealUnavailable(error)
        }

        let policy: UploadPolicy
        do {
            policy = try await blob.uploadPolicy()
        } catch {
            try Task.checkCancellation()
            throw ChatMediaUploadError.failed(error)
        }

        if chatSeal != nil {
            guard let encrypted = policy.encrypted else {
                logger.warning("Upload policy allows no encrypted chat photo", metadata: ["policyVersion": "\(policy.version)"])
                throw ChatMediaUploadError.encryptionNotAllowed
            }
            // The ceiling covers the sealed blob, so the image must leave room for nonce and tag.
            return (chatSeal, encrypted.image, encrypted.maxSizeBytes - EncryptedBlobUpload.overhead)
        } else {
            guard let constraint = policy.constraint(for: ChatMediaEncoder.mimeType) else {
                logger.warning("Upload policy accepts no chat photo", metadata: ["policyVersion": "\(policy.version)"])
                throw ChatMediaUploadError.noMatchingConstraint
            }
            return (nil, constraint.image, constraint.maxSizeBytes)
        }
    }

    private func storeAndFinalize(
        _ data: Data,
        width: Int,
        height: Int,
        chatSeal: ChatSeal?,
        progress: ChatPhotoSendProgress?,
        onStored: (UploadedPhoto) -> Void
    ) async throws -> UploadedPhoto {
        // Byte counts arrive on URLSession's delegate queue.
        let onBytes: @Sendable (BlobUploadProgress) -> Void = { [weak progress] bytes in
            Task { @MainActor in progress?.didUpload(bytes) }
        }

        let uploaded: UploadedPhoto
        if let chatSeal {
            let blurhash = await Self.blurhash(of: data)
            let stored = try await store(progress: progress) { try await blob.storeEncryptedBlob(data, seal: chatSeal, onProgress: onBytes) }
            uploaded = .sealed(SealedPhoto(
                blobID: stored.blobID,
                mimeType: ChatMediaEncoder.mimeType,
                sizeBytes: stored.plaintextSize,
                width: width,
                height: height,
                blurhash: blurhash
            ))
        } else {
            uploaded = .plain(try await store(progress: progress) { try await blob.storeBlob(data, mimeType: ChatMediaEncoder.mimeType, onProgress: onBytes) })
        }

        onStored(uploaded)
        return try await finalize(uploaded, progress: progress)
    }

    /// Returns `photo` once the server has finalized its stored bytes, throwing
    /// `ChatMediaUploadError`.
    func finalize(_ photo: UploadedPhoto, progress: ChatPhotoSendProgress? = nil) async throws -> UploadedPhoto {
        progress?.beginProcessing()

        do {
            try await blob.awaitBlobFinalization(blobID: photo.blobID)
        } catch ErrorBlob.rejected(let reason) {
            throw ChatMediaUploadError.rejected(reason)
        } catch {
            try Task.checkCancellation()
            throw ChatMediaUploadError.failed(error)
        }

        return photo
    }

    /// Stores `data`, retrying through `backoff` while the failure is in transit.
    private func store<Stored>(progress: ChatPhotoSendProgress?, _ attemptStore: () async throws -> Stored) async throws -> Stored {
        var attempt = 0
        while true {
            // A retried store sends every byte again.
            progress?.beginAttempt()
            do {
                return try await attemptStore()
            } catch {
                try Task.checkCancellation()

                if let error = error as? ErrorBlob {
                    switch error {
                    case .rejected(let reason):
                        throw ChatMediaUploadError.rejected(reason)
                    case .network, .uploadFailed, .timedOut, .unknown:
                        break
                    case .uploadDenied, .unsupportedType, .tooLarge, .quotaExceeded, .notFound, .notUploaded:
                        throw ChatMediaUploadError.failed(error)
                    }
                }

                guard attempt < backoff.count else {
                    throw ChatMediaUploadError.failed(error)
                }

                logger.info("Retrying chat photo store", metadata: [
                    "attempt": "\(attempt + 1)",
                    "error": "\(error)",
                ])
                try await Task.sleep(for: backoff[attempt])
                attempt += 1
            }
        }
    }

    /// Encodes off the main actor, since drawing and compressing a full-size photo takes a while.
    @concurrent
    private nonisolated static func encode(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        target: ChatMediaDownscale.Target,
        maxSizeBytes: Int
    ) async throws -> Data {
        try ChatMediaEncoder().encode(image, orientation: orientation, target: target, maxSizeBytes: maxSizeBytes)
    }

    /// The BlurHash of the encoded photo, which a recipient of an encrypted photo draws until it
    /// decrypts, since the server cannot derive one. Empty when the bytes don't decode, which the
    /// contract allows.
    @concurrent
    nonisolated static func blurhash(of jpeg: Data) async -> String {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary) else { return "" }
        let landscape = thumbnail.width >= thumbnail.height
        return BlurHash.encode(thumbnail, componentsX: landscape ? 4 : 3, componentsY: landscape ? 3 : 4) ?? ""
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
