//
//  ChatMediaUploader.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import ImageIO
import FlipcashCore

private let logger = Logger(label: "flipcash.chat-media-upload")

/// The blob calls a chat photo upload makes, in the order it makes them.
///
/// The owner is bound by the conformer, so the upload never handles keys.
protocol ChatMediaBlobStoring {

    /// Returns the upload constraints in force for the owner.
    func uploadPolicy() async throws -> UploadPolicy

    /// Stores `data` and returns its blob, before the server has finalized it.
    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID

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

    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }
}

/// Why a chat photo did not upload.
enum ChatMediaUploadError: Error {
    /// The upload policy accepts no JPEG.
    case noMatchingConstraint
    /// The photo could not be encoded within the policy's size ceiling.
    case encodingFailed(ChatMediaEncoder.Error)
    /// The server refused the stored bytes.
    case rejected(BlobRejectionReason)
    /// The upload failed for a reason other than the bytes themselves, after any automatic retries.
    case failed(Error)

    /// Whether uploading the same photo again could succeed.
    var isRetryable: Bool {
        switch self {
        case .noMatchingConstraint, .encodingFailed:
            false
        case .rejected(let reason):
            switch reason {
            case .moderation:
                false
            case .unsupportedType, .mismatchedType, .tooLarge, .corrupt, .privacyMetadata, .unknown:
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
        case .noMatchingConstraint, .encodingFailed:
            .error
        case .rejected:
            .info
        case .failed(let error):
            (error as? ServerError)?.reportingLevel ?? .error
        }
    }
}

/// Turns a staged photo into a finalized blob: downscaled to the upload policy's bounds, encoded
/// down the JPEG quality ladder, stored, and awaited until the server has finalized it.
struct ChatMediaUploader {

    let blob: any ChatMediaBlobStoring

    /// The wait before each automatic retry of a store that failed in transit; one entry per retry.
    var backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

    /// Returns the finalized blob for `image`, throwing `ChatMediaUploadError`.
    ///
    /// `onPrepared` receives the uploaded pixel width and height once, before any bytes are stored.
    func upload(_ image: UIImage, onPrepared: (Int, Int) -> Void) async throws -> BlobID {
        let policy: UploadPolicy
        do {
            policy = try await blob.uploadPolicy()
        } catch {
            try Task.checkCancellation()
            throw ChatMediaUploadError.failed(error)
        }

        guard let constraint = policy.constraint(for: ChatMediaEncoder.mimeType) else {
            logger.warning("Upload policy accepts no chat photo", metadata: ["policyVersion": "\(policy.version)"])
            throw ChatMediaUploadError.noMatchingConstraint
        }
        guard let cgImage = image.cgImage else {
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
            maxWidth: constraint.image?.maxWidth ?? 0,
            maxHeight: constraint.image?.maxHeight ?? 0,
            maxPixels: constraint.image?.maxPixels ?? 0
        )
        onPrepared(target.width, target.height)

        let data: Data
        do {
            data = try await Self.encode(cgImage, orientation: orientation, target: target, maxSizeBytes: constraint.maxSizeBytes)
        } catch let error as ChatMediaEncoder.Error {
            throw ChatMediaUploadError.encodingFailed(error)
        }

        let blobID = try await store(data)

        do {
            try await blob.awaitBlobFinalization(blobID: blobID)
        } catch ErrorBlob.rejected(let reason) {
            throw ChatMediaUploadError.rejected(reason)
        } catch {
            try Task.checkCancellation()
            throw ChatMediaUploadError.failed(error)
        }

        return blobID
    }

    /// Stores `data`, retrying through `backoff` while the failure is in transit.
    private func store(_ data: Data) async throws -> BlobID {
        var attempt = 0
        while true {
            do {
                return try await blob.storeBlob(data, mimeType: ChatMediaEncoder.mimeType)
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
