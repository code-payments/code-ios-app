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

    /// The payments host + port for the transient mint-metadata connection (see `fetchMintMetadata`),
    /// stored as plain values since `Network` isn't `Sendable`.
    private let paymentsHost: String
    private let port: Int
    private let messagingService: ChatMessagingService
    private let coreClient: GRPCClient<AppTransport>
    /// The core client's connection loop; retained for its lifetime — dropping it makes the client
    /// inert and every RPC hangs.
    private let coreConnectionTask: Task<Void, Never>

    // MARK: - Init -

    public init(network: Network = .mainNet) throws {
        self.paymentsHost = network.hostForPayments
        self.port = network.port
        // Messaging is served by the core host. The payments host (mint metadata) is reached by a
        // transient client in `fetchMintMetadata`, not a resident connection — a content extension's
        // memory budget can't carry a second connection open for its whole lifetime.
        let coreClient = GRPCClient(
            transport: try GRPCTransport.makeTransportServices(host: network.hostForCore, port: network.port),
            interceptors: [UserAgentClientInterceptor()]
        )
        self.coreClient = coreClient
        self.coreConnectionTask = Task {
            do { try await coreClient.runConnections() }
            catch { logger.error("Core connection loop terminated", metadata: ["error": "\(error)"]) }
        }
        self.messagingService = ChatMessagingService(client: coreClient)
    }

    deinit {
        // Graceful shutdown drains in-flight work before the connection closes; cancelling the
        // task ends the connection loop.
        coreClient.beginGracefulShutdown()
        coreConnectionTask.cancel()
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
        guard !mints.isEmpty else { return [:] }
        // A transient payments connection: opened for this fetch and torn down after, so it never
        // sits resident alongside the core connection in the extension's memory budget.
        let paymentsClient = GRPCClient(
            transport: try GRPCTransport.makeTransportServices(host: paymentsHost, port: port),
            interceptors: [UserAgentClientInterceptor()]
        )
        let connectionTask = Task {
            do { try await paymentsClient.runConnections() }
            catch { logger.error("Payments connection loop terminated", metadata: ["error": "\(error)"]) }
        }
        defer {
            paymentsClient.beginGracefulShutdown()
            connectionTask.cancel()
        }
        let currencyService = CurrencyService(client: paymentsClient)
        return try await withCheckedThrowingContinuation { continuation in
            currencyService.fetchMints(mints: mints) { continuation.resume(with: $0) }
        }
    }
}
