//
//  ChatNotificationClient.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import GRPC

/// A lean gRPC façade for fetching and sending chat messages from a
/// notification extension. Constructs only the `ChatMessagingService` —
/// no `FlipClient` or `Client` graph is required.
public final class ChatNotificationClient {

    private let messagingService: ChatMessagingService

    // MARK: - Init -

    public init(network: Network = .mainNet) {
        let queue = DispatchQueue(label: "flipcash.chat-notification-client", qos: .userInitiated)
        let channel = ClientConnection.appConnection(
            host: network.hostForCore,
            port: network.port
        )
        self.messagingService = ChatMessagingService(channel: channel, queue: queue)
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
}
