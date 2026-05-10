//
//  FlipClient+Moderation.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

extension FlipClient {
    /// Convenience overload that builds `auth` from the owning key pair, so
    /// callers at the view layer don't need to import `FlipcashAPI` to
    /// construct an `Auth` proto.
    public func moderateText(_ text: String, owner: KeyPair) async throws -> ModerationAttestation {
        var request = Flipcash_Moderation_V1_ModerateTextRequest()
        request.text = text
        let auth = owner.authFor(message: request)
        return try await withCheckedThrowingContinuation { c in
            moderationService.moderateText(text, auth: auth) { c.resume(with: $0) }
        }
    }

    /// Convenience overload that builds `auth` from the owning key pair, so
    /// callers at the view layer don't need to import `FlipcashAPI` to
    /// construct an `Auth` proto.
    public func moderateImage(_ imageData: Data, owner: KeyPair) async throws -> ModerationAttestation {
        var request = Flipcash_Moderation_V1_ModerateImageRequest()
        request.imageData = imageData
        let auth = owner.authFor(message: request)
        return try await withCheckedThrowingContinuation { c in
            moderationService.moderateImage(imageData, auth: auth) { c.resume(with: $0) }
        }
    }
}
