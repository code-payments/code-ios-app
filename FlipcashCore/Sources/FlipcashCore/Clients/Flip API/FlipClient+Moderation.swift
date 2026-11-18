//
//  FlipClient+Moderation.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {
    /// Moderates `text` as `kind`. The returned attestation names `kind` and
    /// is valid only where the text is used as that kind.
    public func moderateText(_ text: String, kind: ModerationTextKind, owner: KeyPair) async throws -> ModerationAttestation {
        try await withCheckedThrowingContinuation { c in
            moderationService.moderateText(text, kind: kind, owner: owner) { c.resume(with: $0) }
        }
    }

    /// Moderates `imageData` as `kind`. The returned attestation names `kind`
    /// and is valid only where the image is used as that kind.
    public func moderateImage(_ imageData: Data, kind: ModerationImageKind, owner: KeyPair) async throws -> ModerationAttestation {
        try await withCheckedThrowingContinuation { c in
            moderationService.moderateImage(imageData, kind: kind, owner: owner) { c.resume(with: $0) }
        }
    }
}
