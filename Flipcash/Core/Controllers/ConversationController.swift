//
//  ConversationController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.conversation-controller")

/// Resolves a DM chat to the synced contact's address-book display name.
@MainActor
protocol DMContactNaming: AnyObject {
    /// Returns nil when no synced contact carries that DM chat ID.
    func contactDisplayName(forDMChat conversationID: ConversationID) -> String?
}

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
    @ObservationIgnored private let contactNaming: any DMContactNaming
    @ObservationIgnored private let database: Database
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var hydratingConversationIDs: Set<ConversationID> = []

    init(
        fetching: any ConversationFetching,
        messaging: any ConversationMessaging,
        streaming: any ConversationEventStreaming,
        contactNaming: any DMContactNaming,
        database: Database,
        owner: KeyPair,
        selfUserID: UserID
    ) {
        self.fetching = fetching
        self.messaging = messaging
        self.streaming = streaming
        self.contactNaming = contactNaming
        self.database = database
        self.owner = owner
        self.selfUserID = selfUserID
        hydrateFromDatabase()
    }

    /// Seeds the store from the local cache so the feed, unread state, and
    /// transcripts render before any network round-trip.
    private func hydrateFromDatabase() {
        do {
            let conversations = try database.getConversations()
            guard !conversations.isEmpty else { return }
            store.setFeed(conversations)
            for conversation in conversations {
                let messages = try database.getConversationMessages(conversationID: conversation.id)
                store.mergeMessages(messages, into: conversation.id)
            }
        } catch {
            logger.error("Failed to hydrate conversations from the database")
            ErrorReporting.captureError(error, reason: "Failed to hydrate conversations from the database")
        }
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
                guard let self else { return }
                self.store.apply(event)
                self.persist(event: event)
                self.hydrateIfUnknown(event)
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

    /// Fetches metadata for a conversation the stream referenced before the
    /// feed knows it — a chat just created by the user's first payment to a
    /// contact, or by someone else's first payment to the user — so it joins
    /// the feed (and the picker's Recents) immediately.
    private func hydrateIfUnknown(_ event: ConversationStreamEvent) {
        let conversationID: ConversationID
        switch event {
        case .newMessages(let id, _), .lastActivityChanged(let id, _), .readPointersChanged(let id, _):
            conversationID = id
        case .metadataRefresh:
            return
        }
        guard !store.conversations.contains(where: { $0.id == conversationID }),
              !hydratingConversationIDs.contains(conversationID) else {
            return
        }
        hydratingConversationIDs.insert(conversationID)
        Task {
            defer { hydratingConversationIDs.remove(conversationID) }
            do {
                let conversation = try await fetching.getChat(owner: owner, conversationID: conversationID)
                store.apply(.metadataRefresh(conversation))
                persistConversation(conversationID)
            } catch {
                logger.error("Failed to hydrate conversation referenced by the event stream", metadata: [
                    "conversationID": "\(conversationID)",
                ])
                ErrorReporting.captureError(error, reason: "Failed to hydrate conversation referenced by the event stream")
            }
        }
    }

    // MARK: - Feed

    func loadFeed() async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            let conversations = try await fetching.getDmChatFeed(owner: owner)
            store.setFeed(conversations)
            persist { try database.replaceConversationFeed(store.conversations) }
        } catch {
            logger.error("Failed to load conversation feed")
            ErrorReporting.captureError(error, reason: "Failed to load conversation feed")
        }
    }

    // MARK: - Persistence

    /// Mirror a stream event into the local cache, from the store's
    /// post-`apply` state so monotonic rules (read pointers) hold.
    private func persist(event: ConversationStreamEvent) {
        switch event {
        case .newMessages(let conversationID, let messages):
            persist { try database.upsertConversationMessages(messages, conversationID: conversationID) }
            persistConversation(conversationID)
        case .metadataRefresh(let conversation):
            persistConversation(conversation.id)
        case .lastActivityChanged(let conversationID, _),
             .readPointersChanged(let conversationID, _):
            persistConversation(conversationID)
        }
    }

    /// Persist the store's current version of a conversation. No-ops for
    /// conversations the store doesn't know yet — `hydrateIfUnknown` follows
    /// up with the fetched metadata.
    private func persistConversation(_ conversationID: ConversationID) {
        guard let conversation = store.conversations.first(where: { $0.id == conversationID }) else { return }
        persist { try database.upsertConversation(conversation) }
    }

    private func persist(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            logger.error("Failed to persist conversation state")
            ErrorReporting.captureError(error, reason: "Failed to persist conversation state")
        }
    }

    // MARK: - Names

    /// Counterpart name shown when neither the synced contacts nor the feed
    /// provides one.
    static let fallbackCounterpartName = "Flipcash User"

    /// The counterpart's name for a conversation: the synced contact's
    /// address-book name, else the server-provided member name from the feed,
    /// else a generic fallback.
    func displayName(for conversation: Conversation) -> String {
        if let contactName = contactName(for: conversation.id) {
            return contactName
        }
        guard let counterpart = conversation.counterpart(excluding: selfUserID),
              !counterpart.displayName.isEmpty else {
            return Self.fallbackCounterpartName
        }
        return counterpart.displayName
    }

    func displayName(forConversationID conversationID: ConversationID) -> String {
        if let conversation = store.conversations.first(where: { $0.id == conversationID }) {
            return displayName(for: conversation)
        }
        return contactName(for: conversationID) ?? Self.fallbackCounterpartName
    }

    private func contactName(for conversationID: ConversationID) -> String? {
        guard let name = contactNaming.contactDisplayName(forDMChat: conversationID),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    // MARK: - Conversation

    func messages(for conversationID: ConversationID) -> [ConversationMessage] {
        store.messages(for: conversationID)
    }

    func loadMessages(for conversationID: ConversationID) async {
        do {
            let messages = try await messaging.getMessages(owner: owner, conversationID: conversationID)
            store.mergeMessages(messages, into: conversationID)
            persist { try database.upsertConversationMessages(messages, conversationID: conversationID) }
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
            persist { try database.upsertConversationMessages([message], conversationID: conversationID) }
            persistConversation(conversationID)
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
            persistConversation(conversationID)
        }
    }
}
