//
//  ChatNotificationClient.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import GRPCCore

private nonisolated let logger = Logger(label: "flipcash.chat-notification-client")

/// A lean gRPC façade for a notification extension: fetches and sends chat messages
/// and resolves mint metadata over its own clients — no `FlipClient`, `Client`, or
/// SQLite `Database` graph is required.
public final class ChatNotificationClient: Sendable {

    private let messagingService: ChatMessagingService
    private let currencyService: CurrencyService
    private let coreClient: GRPCClient<AppTransport>
    private let paymentsClient: GRPCClient<AppTransport>
    /// The clients' connection loops; retained for the clients' lifetime — dropping them
    /// makes the clients inert and every RPC hangs.
    private let connectionTasks: [Task<Void, Never>]

    // MARK: - Init -

    public init(network: Network = .mainNet) throws {
        // Messaging is served by the core host, currency (mint metadata) by the payments host.
        let coreClient = GRPCClient(
            transport: try GRPCTransport.makeTransportServices(host: network.hostForCore, port: network.port),
            interceptors: [UserAgentClientInterceptor()]
        )
        let paymentsClient = GRPCClient(
            transport: try GRPCTransport.makeTransportServices(host: network.hostForPayments, port: network.port),
            interceptors: [UserAgentClientInterceptor()]
        )
        self.coreClient = coreClient
        self.paymentsClient = paymentsClient
        self.connectionTasks = [
            Task {
                do { try await coreClient.runConnections() }
                catch { logger.error("Core connection loop terminated", metadata: ["error": "\(error)"]) }
            },
            Task {
                do { try await paymentsClient.runConnections() }
                catch { logger.error("Payments connection loop terminated", metadata: ["error": "\(error)"]) }
            },
        ]
        self.messagingService = ChatMessagingService(client: coreClient)
        self.currencyService = CurrencyService(client: paymentsClient)
    }

    deinit {
        // Graceful shutdown drains in-flight streams before the connections close; cancelling
        // the tasks ends the connection loops.
        coreClient.beginGracefulShutdown()
        paymentsClient.beginGracefulShutdown()
        connectionTasks.forEach { $0.cancel() }
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
                text: text,
                clientMessageID: UUID()
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
