//
//  GroupKeyEnvelopeStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Where the signed-in user's private-group key envelopes are kept between launches, so an
/// encrypted chat opens offline.
///
/// It holds the envelope as the server returned it, never the unwrapped chat key: the key is opened
/// from the envelope with the owner key each launch, with the same checks as a fetched one.
public protocol GroupKeyEnvelopeStore: Sendable {
    /// The envelope stored for `conversationID`, or nil when none is stored or it no longer decodes.
    func material(for conversationID: ConversationID) throws -> GroupKeyMaterial?
    /// Stores `material` for `conversationID`, replacing any earlier one.
    func store(_ material: GroupKeyMaterial, for conversationID: ConversationID) throws
    /// Removes whatever is stored for `conversationID`.
    func remove(for conversationID: ConversationID) throws
}

extension GroupKeyMaterial {

    /// The material as the bytes of the `GetKeyEnvelopeResponse` the server returns it in.
    public func serialized() throws -> Data {
        var response = Flipcash_Chat_V1_GetKeyEnvelopeResponse()
        response.result = .ok
        switch self {
        case .own(let envelope, let wrappedBy):
            response.keyEnvelope = envelope.proto
            if let wrappedBy { response.wrappedBy = wrappedBy.proto }
        case .invite(let bundle, let wrappedBy, let wrappedByPublicKey):
            response.inviteKeyBundle = .with {
                $0.inviteID = bundle.inviteID.proto
                $0.keyEnvelope = bundle.keyEnvelope.proto
                $0.secretEnvelope = bundle.secretEnvelope.proto
            }
            if let wrappedBy { response.wrappedBy = wrappedBy.proto }
            if let wrappedByPublicKey { response.wrappedByPublicKey = wrappedByPublicKey.proto }
        }
        return try response.serializedData()
    }

    /// The material `serialized()` wrote, or nil when `data` is not a response carrying an envelope.
    public init?(serialized data: Data) {
        guard let response = try? Flipcash_Chat_V1_GetKeyEnvelopeResponse(serializedBytes: data) else { return nil }
        let wrappedBy = response.hasWrappedBy ? try? UserID(data: response.wrappedBy.value) : nil
        let wrappedByPublicKey = response.hasWrappedByPublicKey ? try? PublicKey(response.wrappedByPublicKey.value) : nil
        switch response.envelope {
        case .keyEnvelope(let envelope):
            self = .own(envelope: ConversationKeyEnvelope(envelope), wrappedBy: wrappedBy)
        case .inviteKeyBundle(let bundle):
            self = .invite(InviteKeyBundle(bundle), wrappedBy: wrappedBy, wrappedByPublicKey: wrappedByPublicKey)
        case nil:
            return nil
        }
    }
}
