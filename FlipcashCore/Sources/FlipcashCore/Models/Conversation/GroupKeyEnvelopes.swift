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

    /// Opens the invite's copy of `conversationID`'s chat key for `owner`. `wrappedByCreator` is
    /// whether the bundle's wrapper is the group's creator. Throws ``GroupKeyUnusable`` when the
    /// bundle fails any check.
    func open(_ bundle: InviteKeyBundle, owner: KeyPair, creatorPublicKey: PublicKey, wrappedByCreator: Bool, conversationID: ConversationID) throws -> Data
}

/// What the server holds for the viewer in a private group: their own envelope, or, after joining
/// by invite and before storing one, the invite's copy of the chat key.
public enum GroupKeyMaterial: Sendable {
    case own(envelope: ConversationKeyEnvelope, wrappedBy: UserID?)
    case invite(InviteKeyBundle, wrappedBy: UserID?, wrappedByPublicKey: PublicKey?)
}

/// Thrown when the stored envelope was wrapped by someone other than the viewer or the group's
/// creator, the only wrappers a member trusts.
public struct GroupKeyNotSelfWrapped: Error {}

/// Thrown when the invite's copy of the chat key failed a check: a wrapper other than the creator,
/// a bad signature, or an envelope that won't open. The viewer is a member with no usable key, and
/// fetching again won't change that.
public struct GroupKeyUnusable: Error, Equatable {
    public enum Step: Sendable, Equatable {
        case wrappedBy, signature, secretOpen, keyOpen
    }

    /// The check the bundle failed.
    public let failsAt: Step

    public init(failsAt: Step) {
        self.failsAt = failsAt
    }
}

/// Thrown when an invite bundle can't be opened yet: this instance doesn't open bundles, or the
/// group's creator isn't known. A later fetch may succeed.
public struct InviteBundleNotOpened: Error {}

/// The signed-in user's private-group chat keys, held in memory only.
///
/// A key is never written to disk: the server keeps the viewer's self-wrapped envelope, which
/// opens with the owner key, so after a relaunch the key is fetched and opened again on first use.
/// A creator whose key was lost before its envelope landed sees `noEnvelope` and generates a new
/// one; nothing was encrypted under the lost key.
///
/// A member who joined by invite holds only the invite's copy of the key until they store their
/// own envelope. It is opened and re-wrapped for the viewer on first use; until that write lands,
/// each launch opens the invite's copy again.
public actor GroupKeyEnvelopes {

    public typealias SetEnvelope = @Sendable (ConversationID, ConversationKeyEnvelope) async throws -> Void
    public typealias GetEnvelope = @Sendable (ConversationID) async throws -> GroupKeyMaterial
    /// Fetches a user's Ed25519 public key, used to open the envelope a creator wrapped.
    public typealias ResolveKey = @Sendable (UserID) async throws -> PublicKey

    private let sealer: any GroupKeySealing
    private let owner: KeyPair
    private let selfUserID: UserID
    private let setEnvelope: SetEnvelope
    private let getEnvelope: GetEnvelope
    private let resolveKey: ResolveKey
    private let opensInviteBundles: Bool

    private var keys: [ConversationID: Data] = [:]

    public init(
        sealer: any GroupKeySealing,
        owner: KeyPair,
        selfUserID: UserID,
        setEnvelope: @escaping SetEnvelope,
        getEnvelope: @escaping GetEnvelope,
        resolveKey: @escaping ResolveKey,
        opensInviteBundles: Bool = true
    ) {
        self.sealer = sealer
        self.owner = owner
        self.selfUserID = selfUserID
        self.setEnvelope = setEnvelope
        self.getEnvelope = getEnvelope
        self.resolveKey = resolveKey
        self.opensInviteBundles = opensInviteBundles
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
        let key = try await groupKey(for: conversationID, creator: selfUserID)
        return try sealer.wrap(groupKey: key, owner: owner, recipient: recipient, conversationID: conversationID)
    }

    /// The viewer's copy of `conversationID`'s chat key, opened from the envelope stored for them.
    ///
    /// A self-wrapped envelope opens with the owner key. One `creator` wrapped at admission opens
    /// with the creator's public key and is then re-wrapped for the viewer, best effort, so later
    /// fetches need only the owner key. Any other wrapper throws ``GroupKeyNotSelfWrapped``. When
    /// the viewer is `creator` and no envelope exists yet, a new key is generated and stored.
    ///
    /// The invite's copy is opened the same way, then re-wrapped for the viewer, best effort. One
    /// that fails a check throws ``GroupKeyUnusable``.
    public func groupKey(for conversationID: ConversationID, creator: UserID?) async throws -> Data {
        if let key = keys[conversationID] {
            return key
        }
        let stored: GroupKeyMaterial
        do {
            stored = try await getEnvelope(conversationID)
        } catch ErrorGetKeyEnvelope.noEnvelope where creator == selfUserID {
            try await storeNewKey(for: conversationID)
            if let key = keys[conversationID] {
                return key
            }
            stored = try await getEnvelope(conversationID)
        }

        let key: Data
        switch stored {
        case .own(let envelope, let wrappedBy):
            if wrappedBy == nil || wrappedBy == selfUserID {
                key = try sealer.unwrap(envelope, owner: owner, wrapper: owner.publicKey, conversationID: conversationID)
            } else if let wrappedBy, wrappedBy == creator {
                let creatorKey = try await resolveKey(wrappedBy)
                key = try sealer.unwrap(envelope, owner: owner, wrapper: creatorKey, conversationID: conversationID)
                await storeSelfWrapped(key, in: conversationID)
            } else {
                throw GroupKeyNotSelfWrapped()
            }
        case .invite(let bundle, let wrappedBy, let wrappedByPublicKey):
            key = try await open(bundle, wrappedBy: wrappedBy, wrappedByPublicKey: wrappedByPublicKey, creator: creator, in: conversationID)
            await storeSelfWrapped(key, in: conversationID)
        }
        keys[conversationID] = key
        return key
    }

    /// The chat key in the invite's copy, checked in the contract's order: the inviter must be the
    /// group's creator before any key is looked at. The creator's key is the one resolved for them
    /// when it can be, otherwise the one the server sent with the bundle; the contract accepts that
    /// the server could report a false key there, the same trust every envelope rests on.
    private func open(_ bundle: InviteKeyBundle, wrappedBy: UserID?, wrappedByPublicKey: PublicKey?, creator: UserID?, in conversationID: ConversationID) async throws -> Data {
        guard opensInviteBundles, let creator else {
            throw InviteBundleNotOpened()
        }
        guard wrappedBy == creator else {
            throw GroupKeyUnusable(failsAt: .wrappedBy)
        }
        let creatorKey: PublicKey
        do {
            creatorKey = try await resolveKey(creator)
        } catch {
            guard let wrappedByPublicKey else { throw error }
            creatorKey = wrappedByPublicKey
        }
        return try sealer.open(bundle, owner: owner, creatorPublicKey: creatorKey, wrappedByCreator: true, conversationID: conversationID)
    }

    /// Replaces the creator-wrapped envelope with the viewer's own. A failure leaves the creator's
    /// in place, which still opens next time.
    private func storeSelfWrapped(_ key: Data, in conversationID: ConversationID) async {
        guard let envelope = try? sealer.wrap(groupKey: key, owner: owner, recipient: owner.publicKey, conversationID: conversationID) else {
            return
        }
        try? await setEnvelope(conversationID, envelope)
    }
}
