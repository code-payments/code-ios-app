//
//  ChatKeyring.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import SharedCore

/// A peer's public key could not be fetched, so their chat can't be encrypted or decrypted yet.
/// Transient: a later attempt may succeed.
public struct PeerKeyUnavailable: Error, Sendable {
    public let userID: UserID
}

/// Where peers' Ed25519 public keys are kept between launches, shared with the extensions.
public protocol PeerKeyStore: Sendable {
    /// The stored key for `userID`, or nil when none is stored.
    func key(for userID: UserID) -> PublicKey?
    /// Stores `key` for `userID`.
    func store(_ key: PublicKey, for userID: UserID)
}

/// A ``PeerKeyStore`` holding one small file per peer in the App Group container. A user's key
/// never changes, so an entry is never invalidated.
public struct AppGroupPeerKeyStore: PeerKeyStore {

    public init() {}

    public func key(for userID: UserID) -> PublicKey? {
        guard let url = fileURL(for: userID), let data = try? Data(contentsOf: url) else { return nil }
        return try? PublicKey(data)
    }

    public func store(_ key: PublicKey, for userID: UserID) {
        guard let url = fileURL(for: userID) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? key.data.write(to: url, options: .atomic)
    }

    private func fileURL(for userID: UserID) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: NotificationPreviewCache.appGroup)?
            .appendingPathComponent("PeerKeys", isDirectory: true)
            .appendingPathComponent(userID.uuidString)
    }
}

/// Holds the signed-in user's DM encryption: which chats encrypt, each peer's public key, and each
/// chat's ``ChatSeal``. The single place outgoing text is encrypted and incoming text decrypted.
public actor ChatKeyring {

    /// Fetches a user's Ed25519 public key from the server.
    public typealias ResolveKey = @Sendable (UserID) async throws -> PublicKey

    private let cipher: any ChatCipher
    private let owner: KeyPair
    private let selfUserID: UserID
    private let store: any PeerKeyStore
    private let resolveKey: ResolveKey

    private var peerKeys: [UserID: PublicKey] = [:]
    private var seals: [ConversationID: ChatSeal] = [:]

    public init(
        cipher: any ChatCipher = DefaultChatCipher.shared,
        owner: KeyPair,
        selfUserID: UserID,
        store: any PeerKeyStore = AppGroupPeerKeyStore(),
        resolveKey: @escaping ResolveKey
    ) {
        self.cipher = cipher
        self.owner = owner
        self.selfUserID = selfUserID
        self.store = store
        self.resolveKey = resolveKey
    }

    /// The seal to send into `conversation` with, or nil when it is sent in plaintext.
    ///
    /// Throws ``PeerKeyUnavailable`` when the peer's key can't be fetched, and shared-core's error
    /// when the key is unusable; either way the message must not go out in plaintext.
    public func sealForSending(in conversation: Conversation) async throws -> ChatSeal? {
        guard E2eePolicy.shouldEncrypt(conversation) else { return nil }
        return try await seal(for: conversation)
    }

    /// How `conversation`'s encrypted messages open right now, fetching the peer's key if needed.
    public func opener(for conversation: Conversation) async -> ChatOpener {
        do {
            return .seal(try await seal(for: conversation))
        } catch is PeerKeyUnavailable {
            return .awaitingKey
        } catch {
            // No peer to decrypt with (a group), or a key shared-core rejects: nothing will open these.
            return .unsupported
        }
    }

    /// `messages` from `conversation`, opened as ``ChatOpener/open(_:)`` does.
    public func open(_ messages: [ConversationMessage], in conversation: Conversation) async -> [ConversationMessage] {
        guard messages.contains(where: \.isAwaitingDecryption) else { return messages }
        return await opener(for: conversation).open(messages)
    }

    /// `message` from `conversation`, opened as ``ChatOpener/open(_:)`` does.
    public func open(_ message: ConversationMessage, in conversation: Conversation) async -> ConversationMessage {
        await open([message], in: conversation)[0]
    }

    private func seal(for conversation: Conversation) async throws -> ChatSeal {
        if let seal = seals[conversation.id] { return seal }
        switch conversation.type {
        case .group:
            throw NoPeer()
        case .contactDm, .tipDm:
            break
        }
        guard let peerID = conversation.members.lazy.compactMap(\.userID).first(where: { $0 != selfUserID }) else {
            throw NoPeer()
        }
        let peerKey = try await publicKey(for: peerID)
        let seal = try ChatSeal(cipher: cipher, owner: owner, peerPublicKey: peerKey, conversationID: conversation.id, selfUserID: selfUserID)
        seals[conversation.id] = seal
        return seal
    }

    private func publicKey(for userID: UserID) async throws -> PublicKey {
        if let key = peerKeys[userID] { return key }
        if let key = store.key(for: userID) {
            peerKeys[userID] = key
            return key
        }
        let key: PublicKey
        do {
            key = try await resolveKey(userID)
        } catch {
            throw PeerKeyUnavailable(userID: userID)
        }
        peerKeys[userID] = key
        store.store(key, for: userID)
        return key
    }

    private struct NoPeer: Error {}
}

/// Decrypts one chat's messages synchronously, once ``ChatKeyring/opener(for:)`` has fetched what it needs.
public enum ChatOpener: Sendable {
    /// The chat's keys are in hand.
    case seal(ChatSeal)
    /// The peer's key couldn't be fetched; messages stay undecrypted and unmarked, to open later.
    case awaitingKey
    /// Nothing will ever decrypt this chat's messages on this client.
    case unsupported

    /// `messages` with every one awaiting decryption decrypted or marked with why it couldn't be.
    public func open(_ messages: [ConversationMessage]) -> [ConversationMessage] {
        messages.map(open)
    }

    /// `message` decrypted or marked with why it couldn't be; unchanged unless awaiting decryption.
    public func open(_ message: ConversationMessage) -> ConversationMessage {
        guard message.isAwaitingDecryption else { return message }
        switch self {
        case .seal(let seal):  return seal.open(message)
        case .awaitingKey:     return message
        case .unsupported:     return message.opened(.failure(.unsupported))
        }
    }
}
