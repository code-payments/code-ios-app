//
//  BlobService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

final class BlobService: Sendable {

    private let service: Flipcash_Blob_V1_BlobStorage.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Blob_V1_BlobStorage.Client(wrapping: client)
    }
}

// MARK: - BlobReserving -

extension BlobService: BlobReserving {

    func initiateExternalUpload(mimeType: String, sizeBytes: Int, owner: KeyPair) async throws -> ReservedUpload {
        var request = Flipcash_Blob_V1_InitiateExternalUploadRequest()
        request.mimeType  = mimeType
        request.sizeBytes = UInt64(sizeBytes)
        request.auth      = owner.authFor(message: request)

        do {
            let response = try await service.initiateExternalUpload(request, options: .unaryDefault)

            switch response.result {
            case .ok:
                guard let target = UploadTarget(response.uploadTarget) else {
                    throw ErrorBlob.unknown
                }

                return ReservedUpload(
                    blobID: BlobID(data: response.blobID.value),
                    target: target
                )

            case .denied:
                throw ErrorBlob.uploadDenied
            case .unsupportedType:
                throw ErrorBlob.unsupportedType
            case .tooLarge:
                throw ErrorBlob.tooLarge
            case .quotaExceeded:
                throw ErrorBlob.quotaExceeded
            case .UNRECOGNIZED:
                throw ErrorBlob.unknown
            }
        } catch let error as ErrorBlob {
            throw error
        } catch {
            throw ErrorBlob.network(error)
        }
    }

    func completeExternalUpload(blobID: BlobID, owner: KeyPair) async throws -> BlobState {
        var request = Flipcash_Blob_V1_CompleteExternalUploadRequest()
        request.blobID = .with { $0.value = blobID.data }
        request.auth   = owner.authFor(message: request)

        do {
            let response = try await service.completeExternalUpload(request, options: .unaryDefault)

            switch response.result {
            case .ok:
                return BlobState(status: response.status, rejection: response.rejectionMetadata)
            case .notFound:
                throw ErrorBlob.notFound
            case .notUploaded:
                throw ErrorBlob.notUploaded
            case .UNRECOGNIZED:
                throw ErrorBlob.unknown
            }
        } catch let error as ErrorBlob {
            throw error
        } catch {
            throw ErrorBlob.network(error)
        }
    }

    /// Returns a freshly minted download URL for a blob the caller owns.
    ///
    /// Media can arrive without one — the proto leaves the metadata optional —
    /// and the URLs expire, so this is the way to get a usable one.
    func downloadURL(blobID: BlobID, owner: KeyPair) async throws -> URL? {
        let blob = try await fetchBlob(blobID: blobID, owner: owner)

        guard let blob, blob.hasMetadata, blob.metadata.hasDownloadURL else {
            return nil
        }

        return URL(string: blob.metadata.downloadURL.url)
    }

    func blobState(blobID: BlobID, owner: KeyPair) async throws -> BlobState {
        // Unauthorized or unknown ids are omitted rather than reported.
        guard let blob = try await fetchBlob(blobID: blobID, owner: owner) else {
            throw ErrorBlob.notFound
        }

        return BlobState(status: blob.status, rejection: blob.rejection)
    }

    /// Returns the blob record for `blobID`, or nil when the server omitted it.
    private func fetchBlob(blobID: BlobID, owner: KeyPair) async throws -> Flipcash_Blob_V1_Blob? {
        var request = Flipcash_Blob_V1_GetBlobsRequest()
        request.blobIds = .with { $0.blobIds = [.with { $0.value = blobID.data }] }
        request.auth    = owner.authFor(message: request)

        do {
            let response = try await service.getBlobs(request, options: .unaryDefault)

            switch response.result {
            case .ok:
                return response.blobs.blobs.first
            case .denied:
                throw ErrorBlob.uploadDenied
            case .UNRECOGNIZED:
                throw ErrorBlob.unknown
            }
        } catch let error as ErrorBlob {
            throw error
        } catch {
            throw ErrorBlob.network(error)
        }
    }
}

// MARK: - Errors -

public enum ErrorBlob: Error, Sendable {
    case uploadDenied
    case unsupportedType
    case tooLarge
    case quotaExceeded
    case notFound
    case notUploaded
    case rejected(BlobRejectionReason)
    case uploadFailed(Int)
    case timedOut
    case unknown
    case network(Error)
}

extension ErrorBlob: ServerError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .uploadDenied, .unsupportedType, .tooLarge, .quotaExceeded,
             .notFound, .notUploaded, .rejected, .uploadFailed, .timedOut:
            .info
        case .unknown:
            .error
        case .network(let error):
            error.wrappedReportingLevel
        }
    }
}
