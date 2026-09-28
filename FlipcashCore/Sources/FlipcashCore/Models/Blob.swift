//
//  Blob.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Where a blob is in its lifecycle.
enum BlobState: Sendable, Equatable {
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
struct ReservedUpload: Sendable, Equatable {
    let blobID: BlobID
    let target: UploadTarget
}

/// The HTTP request that uploads a blob's bytes directly to storage.
///
/// A bearer credential — anyone holding it can write to the reserved key until
/// it expires, so it is never persisted or shared.
struct UploadTarget: Sendable, Equatable {
    let url: URL
    let headers: [String: String]
    let formFields: [String: String]

    init(url: URL, headers: [String: String], formFields: [String: String]) {
        self.url        = url
        self.headers    = headers
        self.formFields = formFields
    }
}

/// The upload constraints in force for a caller, fetched with `GetUploadPolicy`.
public struct UploadPolicy: Sendable, Equatable {

    /// The bounds one MIME-type pattern imposes on a matching upload.
    public struct MimeConstraint: Sendable, Equatable {
        public let pattern: String
        public let maxSizeBytes: Int
        public let image: ImageConstraints?
    }

    /// Pixel bounds on an image upload; `0` on an axis means unbounded.
    public struct ImageConstraints: Sendable, Equatable {
        public let maxWidth: Int
        public let maxHeight: Int
        public let maxPixels: Int
    }

    /// Opaque generation token, compared by equality only.
    public let version: String

    /// How long the policy may be relied on, or nil when the server sent none.
    public let ttl: Duration?

    /// Constraints ordered most specific first.
    public let constraints: [MimeConstraint]

    init(version: String, ttl: Duration?, constraints: [MimeConstraint]) {
        self.version     = version
        self.ttl         = ttl
        self.constraints = constraints
    }

    /// Returns the constraint governing `mimeType` — the first match in policy
    /// order — or nil when the policy accepts no upload of that type.
    public func constraint(for mimeType: String) -> MimeConstraint? {
        ChatMediaConstraints.firstMatchIndex(patterns: constraints.map(\.pattern), mimeType: mimeType)
            .map { constraints[$0] }
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

extension UploadPolicy {
    init(_ proto: Flipcash_Blob_V1_UploadPolicy) {
        self.init(
            version: proto.version.value,
            ttl: proto.hasTtl ? .seconds(proto.ttl.seconds) + .nanoseconds(proto.ttl.nanos) : nil,
            constraints: proto.mimeTypeConstraints.map(MimeConstraint.init)
        )
    }
}

extension UploadPolicy.MimeConstraint {
    init(_ proto: Flipcash_Blob_V1_MimeTypeConstraints) {
        let image: UploadPolicy.ImageConstraints?
        switch proto.kind {
        case .image(let bounds):
            image = UploadPolicy.ImageConstraints(
                maxWidth: Int(bounds.maxWidth),
                maxHeight: Int(bounds.maxHeight),
                maxPixels: Int(clamping: bounds.maxPixels)
            )
        case nil:
            image = nil
        }

        self.init(
            pattern: proto.mimeTypePattern,
            maxSizeBytes: Int(clamping: proto.maxSizeBytes),
            image: image
        )
    }
}
