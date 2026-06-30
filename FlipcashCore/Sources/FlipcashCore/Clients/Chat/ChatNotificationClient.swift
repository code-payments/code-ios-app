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

    /// Thrown internally when a retry-on-empty read comes back empty, so `Task.retry` re-fetches.
    private struct EmptyMessages: Error {}

    /// Returns the newest `limit` messages in a conversation, oldest-first. When `retryingEmpty` is
    /// set, an empty read is retried a few times (250ms apart) to dodge the read-after-write race
    /// against a message that *just* arrived; a persistent empty result returns `[]`, not an error.
    public func getMessages(
        owner: KeyPair,
        conversationID: ConversationID,
        limit: Int = 3,
        retryingEmpty: Bool = false
    ) async throws -> [ConversationMessage] {
        guard retryingEmpty else {
            return try await fetchMessages(owner: owner, conversationID: conversationID, limit: limit)
        }
        do {
            return try await Task.retry(maxAttempts: 4, delay: .milliseconds(250)) {
                let messages = try await fetchMessages(owner: owner, conversationID: conversationID, limit: limit)
                if messages.isEmpty { throw EmptyMessages() }
                return messages
            }
        } catch is EmptyMessages {
            return []
        }
    }

    private func fetchMessages(
        owner: KeyPair,
        conversationID: ConversationID,
        limit: Int
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

    /// Sends a text message and returns the server-confirmed `ConversationMessage`. `clientMessageID`
    /// must stay stable across retries so the server dedups the send — generate it once at the call site.
    @discardableResult
    public func sendMessage(
        owner: KeyPair,
        conversationID: ConversationID,
        text: String,
        clientMessageID: UUID
    ) async throws -> ConversationMessage {
        try await withCheckedThrowingContinuation { continuation in
            messagingService.sendMessage(
                owner: owner,
                conversationID: conversationID,
                text: text,
                clientMessageID: clientMessageID
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

    /// Resolves token branding (name + icon) for any cash mints in `messages`, so cash rows can show
    /// their token label + icon. An unresolved or absent mint is simply omitted. Throws on a transport
    /// failure so each call site applies its own error policy.
    public func resolveMintBranding(
        in messages: [ConversationMessage]
    ) async throws -> [PublicKey: MintBrandingInfo] {
        let mints = Set(messages.compactMap { message -> PublicKey? in
            guard case .cash(let fiat) = message.content else { return nil }
            return fiat.mint
        })
        guard !mints.isEmpty else { return [:] }
        let resolved = try await fetchMintMetadata(for: Array(mints))
        return resolved.mapValues { MintBrandingInfo(name: $0.name, iconURL: $0.imageURL) }
    }
}
