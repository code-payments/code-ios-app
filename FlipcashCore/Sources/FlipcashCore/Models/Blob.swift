//
//  Blob.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Where a blob is in its lifecycle.
public enum BlobState: Sendable, Equatable {
    case pending
    case processing
    case ready
    case rejected(BlobRejectionReason)
}

/// Why finalization refused a blob after its bytes were stored.
///
/// Terminal: the bytes behind a blob are immutable, so a rejected blob never
/// becomes ready and a retry must reserve a fresh upload.
public enum BlobRejectionReason: Sendable, Equatable {
    case moderation
    case unsupportedType
    case mismatchedType
    case tooLarge
    case corrupt
    case privacyMetadata
    case unknown
}

/// A reserved upload: the blob it will become, and the request that stores its
/// bytes.
public struct ReservedUpload: Sendable, Equatable {
    public let blobID: BlobID
    public let target: UploadTarget
}

/// The HTTP request that uploads a blob's bytes directly to storage.
///
/// A bearer credential — anyone holding it can write to the reserved key until
/// it expires, so it is never persisted or shared.
public struct UploadTarget: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public let formFields: [String: String]

    public init(url: URL, headers: [String: String], formFields: [String: String]) {
        self.url        = url
        self.headers    = headers
        self.formFields = formFields
    }
}

// MARK: - Proto -

extension BlobState {
    init(status: Flipcash_Blob_V1_BlobStatus, rejection: Flipcash_Blob_V1_RejectionMetadata) {
        switch status {
        case .pending:
            self = .pending
        case .processing:
            self = .processing
        case .ready:
            self = .ready
        case .rejected:
            self = .rejected(BlobRejectionReason(rejection.reason))
        case .unknown, .UNRECOGNIZED:
            self = .processing
        }
    }
}

extension BlobRejectionReason {
    init(_ proto: Flipcash_Blob_V1_RejectionReason) {
        switch proto {
        case .moderation:       self = .moderation
        case .unsupportedType:  self = .unsupportedType
        case .mismatchedType:   self = .mismatchedType
        case .tooLarge:         self = .tooLarge
        case .corrupt:          self = .corrupt
        case .privacyMetadata:  self = .privacyMetadata
        case .internal:         self = .unknown
        case .unknown, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension UploadTarget {
    init?(_ proto: Flipcash_Blob_V1_UploadTarget) {
        guard let url = URL(string: proto.url) else {
            return nil
        }

        self.init(
            url: url,
            headers: proto.headers,
            formFields: proto.formFields
        )
    }
}
