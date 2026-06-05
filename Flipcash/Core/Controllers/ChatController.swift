//
//  ChatController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.chat-controller")

/// Session-scoped owner of the DM conversation feed and the single per-user
/// event stream. Holds state in a pure `ConversationStore`, applies live
/// `ChatStreamEvent`s, and resolves counterpart display names.
///
/// Depends on capability protocols (not a concrete client) so it is unit-testable
/// with injected mocks. Inject into views via `@Environment(ChatController.self)`.
@MainActor
@Observable
final class ChatController {

    /// DM conversations, most-recent activity first.
    var conversations: [Conversation] { store.conversations }
    private(set) var isLoadingFeed = false

    /// The signed-in user, used to tell own messages from the counterpart's.
    let selfUserID: UserID

    private var store = ConversationStore()
    /// Counterpart display names resolved from the profile service. Observed so
    /// the feed + conversation title update when a name resolves.
    private var resolvedNames: [UserID: String] = [:]

    @ObservationIgnored private let fetching: any ConversationFetching
    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let streaming: any ConversationEventStreaming
    @ObservationIgnored private let profiles: any ProfileFetching
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(
        fetching: any ConversationFetching,
        messaging: any ConversationMessaging,
        streaming: any ConversationEventStreaming,
        profiles: any ProfileFetching,
        owner: KeyPair,
        selfUserID: UserID
    ) {
        self.fetching = fetching
        self.messaging = messaging
        self.streaming = streaming
        self.profiles = profiles
        self.owner = owner
        self.selfUserID = selfUserID
    }

    // MARK: - Lifecycle

    /// Open the event stream and load the initial feed. Idempotent. The stream
    /// is consumed before the feed is paged so updates landing mid-load aren't
    /// lost (the chat-feed contract).
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
            await resolveNames(for: conversations)
        } catch {
            logger.error("Failed to load conversation feed")
            ErrorReporting.captureError(error, reason: "Failed to load conversation feed")
        }
    }

    // MARK: - Names

    /// The counterpart's name for a conversation: resolved profile name, else
    /// the server-provided member name, else a generic fallback.
    func displayName(for conversation: Conversation) -> String {
        guard let counterpart = conversation.counterpart(excluding: selfUserID) else {
            return "Direct Message"
        }
        if let userID = counterpart.userID, let resolved = resolvedNames[userID], !resolved.isEmpty {
            return resolved
        }
        if !counterpart.displayName.isEmpty {
            return counterpart.displayName
        }
        return "Direct Message"
    }

    func displayName(forChatID chatID: ChatID) -> String {
        guard let conversation = store.conversations.first(where: { $0.id == chatID }) else {
            return "Direct Message"
        }
        return displayName(for: conversation)
    }

    private func resolveNames(for conversations: [Conversation]) async {
        for conversation in conversations {
            guard let userID = conversation.counterpart(excluding: selfUserID)?.userID,
                  resolvedNames[userID] == nil else { continue }
            guard let profile = try? await profiles.fetchProfile(userID: userID, owner: owner),
                  let name = profile.displayName, !name.isEmpty else { continue }
            resolvedNames[userID] = name
        }
    }

    // MARK: - Conversation

    func messages(for chatID: ChatID) -> [ChatMessage] {
        store.messages(for: chatID)
    }

    func loadMessages(for chatID: ChatID) async {
        do {
            let messages = try await messaging.getMessages(owner: owner, chatID: chatID)
            store.mergeMessages(messages, into: chatID)
        } catch {
            logger.error("Failed to load conversation messages")
            ErrorReporting.captureError(error, reason: "Failed to load conversation messages")
        }
    }

    @discardableResult
    func send(_ text: String, to chatID: ChatID) async -> Bool {
        do {
            let message = try await messaging.sendMessage(owner: owner, chatID: chatID, text: text)
            store.mergeMessages([message], into: chatID)
            store.setLastMessage(message, in: chatID)
            return true
        } catch {
            logger.error("Failed to send conversation message")
            ErrorReporting.captureError(error, reason: "Failed to send conversation message")
            return false
        }
    }

    func markRead(chatID: ChatID) async {
        guard let latest = store.messages(for: chatID).last else { return }
        try? await messaging.markRead(owner: owner, chatID: chatID, messageID: latest.id)
    }
}
