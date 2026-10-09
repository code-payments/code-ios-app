//
//  GroupKeyEnvelopes.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The group-key half of the chat cipher: a private group's 32-byte chat key, and the envelopes
/// that carry it to each member.
public protocol GroupKeySealing: Sendable {

    /// 32 fresh random bytes, generated once by a private group's creator.
    func newGroupKey() -> Data

    /// Wraps `groupKey` from `owner` to `recipient` in `conversationID`. Pass `owner`'s own public
    /// key as `recipient` to wrap for oneself.
    func wrap(groupKey: Data, owner: KeyPair, recipient: PublicKey, conversationID: ConversationID) throws -> ConversationKeyEnvelope

    /// Opens an envelope `wrapper` made for `owner` in `conversationID`.
    func unwrap(_ envelope: ConversationKeyEnvelope, owner: KeyPair, wrapper: PublicKey, conversationID: ConversationID) throws -> Data
}

/// Thrown when the stored envelope was wrapped by someone other than the viewer, so it isn't the
/// self-wrapped copy ``GroupKeyEnvelopes`` opens.
public struct GroupKeyNotSelfWrapped: Error {}

/// The signed-in user's private-group chat keys, held in memory only.
///
/// A key is never written to disk: the server keeps the viewer's self-wrapped envelope, which
/// opens with the owner key, so after a relaunch the key is fetched and opened again on first use.
/// A creator whose key was lost before its envelope landed sees `noEnvelope` and generates a new
/// one; nothing was encrypted under the lost key.
public actor GroupKeyEnvelopes {

    public typealias SetEnvelope = @Sendable (ConversationID, ConversationKeyEnvelope) async throws -> Void
    public typealias GetEnvelope = @Sendable (ConversationID) async throws -> (envelope: ConversationKeyEnvelope, wrappedBy: UserID?)

    private let sealer: any GroupKeySealing
    private let owner: KeyPair
    private let selfUserID: UserID
    private let setEnvelope: SetEnvelope
    private let getEnvelope: GetEnvelope

    private var keys: [ConversationID: Data] = [:]

    public init(
        sealer: any GroupKeySealing,
        owner: KeyPair,
        selfUserID: UserID,
        setEnvelope: @escaping SetEnvelope,
        getEnvelope: @escaping GetEnvelope
    ) {
        self.sealer = sealer
        self.owner = owner
        self.selfUserID = selfUserID
        self.setEnvelope = setEnvelope
        self.getEnvelope = getEnvelope
    }

    /// Generates `conversationID`'s chat key and stores the creator's own envelope: the second
    /// step of creating a private group.
    ///
    /// `alreadySet` counts as success: the envelope stored first stands, and a retry after a lost
    /// response lands there. The key it holds is opened on first use.
    public func storeNewKey(for conversationID: ConversationID) async throws {
        let key = sealer.newGroupKey()
        let envelope = try sealer.wrap(groupKey: key, owner: owner, recipient: owner.publicKey, conversationID: conversationID)
        do {
            try await setEnvelope(conversationID, envelope)
            keys[conversationID] = key
        } catch ErrorSetKeyEnvelope.alreadySet {
            keys[conversationID] = nil
        }
    }

    /// Wraps `conversationID`'s chat key for `recipient`, for the creator to admit them. A creator
    /// with no envelope stored yet stores one first.
    public func wrap(for recipient: PublicKey, in conversationID: ConversationID) async throws -> ConversationKeyEnvelope {
        let key: Data
        do {
            key = try await groupKey(for: conversationID)
        } catch ErrorGetKeyEnvelope.noEnvelope {
            try await storeNewKey(for: conversationID)
            key = try await groupKey(for: conversationID)
        }
        return try sealer.wrap(groupKey: key, owner: owner, recipient: recipient, conversationID: conversationID)
    }

    /// The viewer's copy of `conversationID`'s chat key, opened from its self-wrapped envelope.
    func groupKey(for conversationID: ConversationID) async throws -> Data {
        if let key = keys[conversationID] {
            return key
        }
        let stored = try await getEnvelope(conversationID)
        guard stored.wrappedBy == nil || stored.wrappedBy == selfUserID else {
            throw GroupKeyNotSelfWrapped()
        }
        let key = try sealer.unwrap(stored.envelope, owner: owner, wrapper: owner.publicKey, conversationID: conversationID)
        keys[conversationID] = key
        return key
    }
}
