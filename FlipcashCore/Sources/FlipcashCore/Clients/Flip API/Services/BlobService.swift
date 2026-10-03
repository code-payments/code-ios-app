//
//  BlobService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

final class BlobService: Sendable {

    private let service: Flipcash_Blob_V1_BlobStorage.Client<AppTransport>
    private let policyCache = UploadPolicyCache()

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Blob_V1_BlobStorage.Client(wrapping: client)
    }
}

// MARK: - BlobReserving -

extension BlobService: BlobReserving {

    func initiateExternalUpload(mimeType: String, sizeBytes: Int, encryptedFor: ConversationID?, owner: KeyPair) async throws -> ReservedUpload {
        let request = Self.initiateRequest(mimeType: mimeType, sizeBytes: sizeBytes, encryptedFor: encryptedFor, owner: owner)

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
                await observePolicyVersion(of: response)
                throw ErrorBlob.unsupportedType
            case .tooLarge:
                await observePolicyVersion(of: response)
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

    /// Returns the upload policy in force for `owner`, from the cache while it
    /// is still valid.
    func uploadPolicy(owner: KeyPair) async throws -> UploadPolicy {
        try await policyCache.policy(for: owner) { [service] in
            var request = Flipcash_Blob_V1_GetUploadPolicyRequest()
            request.auth = owner.authFor(message: request)

            do {
                let response = try await service.getUploadPolicy(request, options: .unaryDefault)

                switch response.result {
                case .ok:
                    return UploadPolicy(response.policy)
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

    /// A policy-driven denial echoes the version in force, which retires a
    /// stale cached policy.
    /// The signed reservation request, naming the DM the bytes are encrypted for when set.
    static func initiateRequest(mimeType: String, sizeBytes: Int, encryptedFor: ConversationID?, owner: KeyPair) -> Flipcash_Blob_V1_InitiateExternalUploadRequest {
        var request = Flipcash_Blob_V1_InitiateExternalUploadRequest()
        request.mimeType  = mimeType
        request.sizeBytes = UInt64(sizeBytes)
        if let encryptedFor {
            request.chat = encryptedFor.proto
        }
        request.auth      = owner.authFor(message: request)
        return request
    }

    private func observePolicyVersion(of response: Flipcash_Blob_V1_InitiateExternalUploadResponse) async {
        guard response.hasPolicyVersion else { return }
        await policyCache.observe(version: response.policyVersion.value)
    }

    /// Returns a freshly minted download URL for a blob the caller owns, or —
    /// with an access context — one it can read through that surface.
    ///
    /// Media can arrive without one — the proto leaves the metadata optional —
    /// and the URLs expire, so this is the way to get a usable one.
    func downloadURL(blobID: BlobID, owner: KeyPair, accessContext: BlobAccessContext? = nil) async throws -> URL? {
        let blob = try await fetchBlob(blobID: blobID, owner: owner, accessContext: accessContext)

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
    private func fetchBlob(blobID: BlobID, owner: KeyPair, accessContext: BlobAccessContext? = nil) async throws -> Flipcash_Blob_V1_Blob? {
        var request = Flipcash_Blob_V1_GetBlobsRequest()
        request.blobIds = .with { $0.blobIds = [.with { $0.value = blobID.data }] }
        if let accessContext {
            request.context = accessContext.proto
        }
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
            // The upload leg is plain HTTP, and a `URLError` bridges to
            // `NSError` once carried here, which drops its `ServerError`
            // conformance — hence the second, concrete cast.
            (error as? ServerError)?.reportingLevel
                ?? (error as? URLError)?.reportingLevel
                ?? .error
        }
    }
}

// MARK: - Access Context -

/// The surface a blob read is authorized through, for blobs the caller does
/// not own. See `flipcash.blob.v1.AccessContext`.
public enum BlobAccessContext: Sendable {

    /// Reading a rendition of `userID`'s current profile picture.
    case userProfile(UserID)

    /// Reading a rendition of `conversationID`'s current group chat profile
    /// picture. Authorized only while the blob is a rendition of that chat's
    /// CURRENT picture; a superseded picture's renditions stop resolving
    /// through it.
    case chatProfile(ConversationID)

    /// Reading media shared into `conversationID` as a message. Authorized
    /// while the caller is a member of the chat.
    case chatMessage(ConversationID)

    var proto: Flipcash_Blob_V1_AccessContext {
        switch self {
        case .userProfile(let userID):
            return .with { $0.userProfile = .with { $0.value = userID.data } }
        case .chatProfile(let conversationID):
            return .with { $0.chatProfile = conversationID.proto }
        case .chatMessage(let conversationID):
            return .with { $0.chat = conversationID.proto }
        }
    }
}
