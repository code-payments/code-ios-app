//
//  ConversationController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.conversation-controller")

/// Session-scoped owner of the DM conversation feed and the single per-user
/// event stream. Holds state in a pure `ConversationStore`, applies live
/// `ConversationStreamEvent`s, and resolves counterpart display names.
///
/// Depends on capability protocols (not a concrete client) so it is unit-testable
/// with injected mocks. Inject into views via `@Environment(ConversationController.self)`.
@MainActor
@Observable
final class ConversationController {

    /// DM conversations, most-recent activity first.
    var conversations: [Conversation] { store.conversations }
    private(set) var isLoadingFeed = false

    /// The signed-in user, used to tell own messages from the counterpart's.
    let selfUserID: UserID

    private var store = ConversationStore()

    @ObservationIgnored private let fetching: any ConversationFetching
    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let streaming: any ConversationEventStreaming
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(
        fetching: any ConversationFetching,
        messaging: any ConversationMessaging,
        streaming: any ConversationEventStreaming,
        owner: KeyPair,
        selfUserID: UserID
    ) {
        self.fetching = fetching
        self.messaging = messaging
        self.streaming = streaming
        self.owner = owner
        self.selfUserID = selfUserID
    }

    // MARK: - Lifecycle

    /// Open the event stream and load the initial feed. Idempotent. The stream
    /// is consumed before the feed is paged so updates landing mid-load aren't
    /// lost (the conversation-feed contract).
    func start() {
        guard streamTask == nil else { return }

        let events = streaming.openConversationStream(owner: owner)
        streamTask = Task { [weak self] in
            for await event in events {
                self?.store.apply(event)
            }
        }

        Task { await loadFeed() }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        streaming.closeConversationStream()
    }

    /// Re-open the stream after returning from background.
    func ensureConnected() {
        streaming.ensureConversationStreamConnected()
    }

    // MARK: - Feed

    func loadFeed() async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            let conversations = try await fetching.getDmChatFeed(owner: owner)
            store.setFeed(conversations)
        } catch {
            logger.error("Failed to load conversation feed")
            ErrorReporting.captureError(error, reason: "Failed to load conversation feed")
        }
    }

    // MARK: - Names

    /// The counterpart's name for a conversation: the server-provided member
    /// name from the feed, else a generic fallback.
    func displayName(for conversation: Conversation) -> String {
        guard let counterpart = conversation.counterpart(excluding: selfUserID),
              !counterpart.displayName.isEmpty else {
            return "Flipcash User"
        }
        return counterpart.displayName
    }

    func displayName(forConversationID conversationID: ConversationID) -> String {
        guard let conversation = store.conversations.first(where: { $0.id == conversationID }) else {
            return "Flipcash User"
        }
        return displayName(for: conversation)
    }

    // MARK: - Conversation

    func messages(for conversationID: ConversationID) -> [ConversationMessage] {
        store.messages(for: conversationID)
    }

    func loadMessages(for conversationID: ConversationID) async {
        do {
            let messages = try await messaging.getMessages(owner: owner, conversationID: conversationID)
            store.mergeMessages(messages, into: conversationID)
        } catch {
            logger.error("Failed to load conversation messages")
            ErrorReporting.captureError(error, reason: "Failed to load conversation messages")
        }
    }

    @discardableResult
    func send(_ text: String, to conversationID: ConversationID) async -> Bool {
        do {
            let message = try await messaging.sendMessage(owner: owner, conversationID: conversationID, text: text)
            store.mergeMessages([message], into: conversationID)
            store.setLastMessage(message, in: conversationID)
            return true
        } catch {
            logger.error("Failed to send conversation message")
            ErrorReporting.captureError(error, reason: "Failed to send conversation message")
            return false
        }
    }

    func markRead(conversationID: ConversationID) async {
        guard let latest = store.messages(for: conversationID).last else { return }
        // Skip the round-trip when the server-known READ watermark already covers
        // the latest message. We advance the watermark locally after each success.
        if let read = store.selfReadPointer(for: conversationID, selfUserID: selfUserID), latest.id <= read {
            return
        }
        if (try? await messaging.markRead(owner: owner, conversationID: conversationID, messageID: latest.id)) != nil {
            store.advanceSelfReadPointer(to: latest.id, in: conversationID, selfUserID: selfUserID)
        }
    }
}
