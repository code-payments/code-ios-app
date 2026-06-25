//
//  ChatNotificationClient.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import GRPC

/// A lean gRPC façade for a notification extension: fetches and sends chat messages
/// and resolves mint metadata over its own channel — no `FlipClient`, `Client`, or
/// SQLite `Database` graph is required.
public final class ChatNotificationClient: @unchecked Sendable {

    private let messagingService: ChatMessagingService
    private let currencyService: CurrencyService

    // MARK: - Init -

    public init(network: Network = .mainNet) {
        let queue = DispatchQueue(label: "flipcash.chat-notification-client", qos: .userInitiated)
        // Messaging is served by the core host, currency (mint metadata) by the payments host.
        // Two channels share the one queue.
        let coreChannel = ClientConnection.appConnection(host: network.hostForCore, port: network.port)
        let paymentsChannel = ClientConnection.appConnection(host: network.hostForPayments, port: network.port)
        self.messagingService = ChatMessagingService(channel: coreChannel, queue: queue)
        self.currencyService = CurrencyService(channel: paymentsChannel, queue: queue)
    }

    // MARK: - Messages -

    /// Returns the newest `limit` messages in a conversation, oldest-first.
    public func getMessages(
        owner: KeyPair,
        conversationID: ConversationID,
        limit: Int = 3
    ) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            messagingService.getMessages(
                owner: owner,
                conversationID: conversationID,
                pageSize: limit,
                pagingToken: nil
            ) { continuation.resume(with: $0) }
        }
    }

    /// Sends a text message and returns the server-confirmed `ConversationMessage`.
    @discardableResult
    public func sendMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        text: String
    ) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { continuation in
            messagingService.sendMessage(
                owner: owner,
                conversationID: conversationID,
                text: text
            ) { continuation.resume(with: $0) }
        }
    }

    // MARK: - Mints -

    /// Resolves token metadata (name, symbol, decimals) for the given mints over the
    /// network — the lean alternative to the app's SQLite mint cache, which an extension
    /// can't reach. Unresolved mints are simply absent from the result.
    public func fetchMintMetadata(for mints: [PublicKey]) async throws -> [PublicKey: MintMetadata] {
        try await withCheckedThrowingContinuation { continuation in
            currencyService.fetchMints(mints: mints) { continuation.resume(with: $0) }
        }
    }
}
