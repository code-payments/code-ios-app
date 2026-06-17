//
//  ConversationController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import SwiftUI
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
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var hydratingConversationIDs: Set<ConversationID> = []
    @ObservationIgnored private var markReadTasks: [ConversationID: Task<Void, Never>] = [:]

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
    }

    /// Seeds the store from the local cache so the feed, unread state, and
    /// transcripts render without a network round-trip. The merge is
    /// animation-suppressed so on-screen surfaces don't play insertion
    /// transitions for cached history.
    func hydrateFromDatabase() async {
        do {
            let cache = try await database.loadConversationCache()
            guard !cache.conversations.isEmpty else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.setFeed(cache.conversations)
                for (conversationID, messages) in cache.messages {
                    store.mergeMessages(messages, into: conversationID)
                }
            }
        } catch {
            logger.error("Failed to load conversation cache", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to load conversation cache")
        }
    }

    // MARK: - Lifecycle

    /// Hydrates from the local cache, opens the event stream, then loads the
    /// feed — in that order so live events aren't lost mid-load. Idempotent.
    func start() {
        guard startTask == nil else { return }
        startTask = Task {
            await hydrateFromDatabase()
            openStream()
            await loadFeed()
        }
    }

    private func openStream() {
        guard streamTask == nil else { return }
        let events = streaming.openConversationStream(owner: owner)
        streamTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.store.apply(event)
                self.persist(event: event)
                self.hydrateIfUnknown(event)
                self.logCounterpartRead(event)
            }
        }
    }

    /// Surfaces a counterpart's READ pointer advance — the signal behind the
    /// "Read 3:42 PM" receipt — so it can be traced in the log stream.
    private func logCounterpartRead(_ event: ConversationStreamEvent) {
        guard case .readPointersChanged(let conversationID, let pointers) = event else { return }
        for pointer in pointers where pointer.userID != selfUserID {
            logger.info("Counterpart advanced read pointer", metadata: [
                "conversationID": "\(conversationID)",
                "messageID": "\(pointer.value.value)",
                "readAt": "\(pointer.date.map { "\($0)" } ?? "nil")",
            ])
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        streamTask?.cancel()
        streamTask = nil
        markReadTasks.values.forEach { $0.cancel() }
        markReadTasks.removeAll()
        streaming.closeConversationStream()
    }

    /// Re-open the stream after returning from background.
    func ensureConnected() {
        streaming.ensureConversationStreamConnected()
    }

    /// Fetches metadata for a conversation the stream referenced before the
    /// feed knows it, so it joins the feed immediately. No-ops for known or
    /// in-flight conversations.
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
                    "error": "\(error)",
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
            persist(operation: "replace-feed") { try database.replaceConversationFeed(store.conversations) }
        } catch {
            logger.error("Failed to load conversation feed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to load conversation feed")
        }
    }

    // MARK: - Persistence

    /// Mirrors a stream event into the local cache. Reads from the store's
    /// post-`apply` state so monotonic rules (read pointers) hold.
    private func persist(event: ConversationStreamEvent) {
        switch event {
        case .newMessages(let conversationID, let messages):
            persist(operation: "upsert-messages") { try database.upsertConversationMessages(messages, conversationID: conversationID) }
            persistConversation(conversationID)
        case .metadataRefresh(let conversation):
            persistConversation(conversation)
        case .lastActivityChanged(let conversationID, _),
             .readPointersChanged(let conversationID, _):
            persistConversation(conversationID)
        }
    }

    /// Persists the store's current version of a conversation. No-ops for
    /// conversations the store doesn't know yet.
    private func persistConversation(_ conversationID: ConversationID) {
        guard let conversation = store.conversations.first(where: { $0.id == conversationID }) else { return }
        persistConversation(conversation)
    }

    private func persistConversation(_ conversation: Conversation) {
        persist(operation: "upsert-conversation") { try database.upsertConversation(conversation) }
    }

    private func persist(operation: String, _ write: () throws -> Void) {
        do {
            try write()
        } catch {
            logger.error("Failed to persist conversation state", metadata: [
                "operation": "\(operation)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to persist conversation state [\(operation)]")
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
            let messages = try await messaging.getMessages(owner: owner, conversationID: conversationID, before: nil)
            store.mergeMessages(messages, into: conversationID)
            persist(operation: "load-messages") { try database.upsertConversationMessages(messages, conversationID: conversationID) }
        } catch {
            logger.error("Failed to load conversation messages", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to load conversation messages")
        }
    }

    // MARK: - Pagination

    /// Per-conversation older-history paging state, observed so the transcript can
    /// show its top loading row and gate re-triggers.
    private struct OlderPageState { var isLoading = false; var hasMore = true }
    private var olderPageState: [ConversationID: OlderPageState] = [:]

    /// Whether older history may still exist server-side. True until an older
    /// page comes back empty (NOT_FOUND).
    func hasMoreOlderMessages(for conversationID: ConversationID) -> Bool {
        olderPageState[conversationID]?.hasMore ?? true
    }

    /// Whether an older page is currently in flight for this conversation.
    func isLoadingOlderMessages(for conversationID: ConversationID) -> Bool {
        olderPageState[conversationID]?.isLoading ?? false
    }

    /// Pages strictly older than the oldest loaded message and prepends the page
    /// to the in-memory window. The newest-100 are the DB cache; older pages are
    /// session-only (persisting them would just be pruned), so a reopen re-pages.
    /// No-ops while a page is in flight or once history is exhausted.
    func loadOlderMessages(for conversationID: ConversationID) async {
        guard hasMoreOlderMessages(for: conversationID), !isLoadingOlderMessages(for: conversationID) else { return }
        guard let oldest = store.messages(for: conversationID).first?.id else { return }

        olderPageState[conversationID, default: OlderPageState()].isLoading = true
        defer { olderPageState[conversationID]?.isLoading = false }

        do {
            let older = try await messaging.getMessages(owner: owner, conversationID: conversationID, before: oldest)
            if older.isEmpty {
                olderPageState[conversationID]?.hasMore = false
            } else {
                // Prepended history must not play insertion transitions — match the
                // animation-suppressed merge used for the cache hydrate.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    store.mergeMessages(older, into: conversationID)
                }
            }
        } catch {
            logger.error("Failed to load older conversation messages", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to load older conversation messages")
        }
    }

    /// Pages the entire older history into the in-memory window, so the transcript
    /// can scroll up to the first message without incremental paging. Stops when a
    /// page makes no progress (e.g. a fetch error) so it can't spin, and honors
    /// cancellation when the conversation is dismissed.
    func loadFullHistory(for conversationID: ConversationID) async {
        var previousOldest: MessageID?
        while hasMoreOlderMessages(for: conversationID), !Task.isCancelled {
            let oldest = store.messages(for: conversationID).first?.id
            guard oldest != previousOldest else { break }
            previousOldest = oldest
            await loadOlderMessages(for: conversationID)
        }
    }

    @discardableResult
    func send(_ text: String, to conversationID: ConversationID) async -> Bool {
        do {
            let message = try await messaging.sendMessage(owner: owner, conversationID: conversationID, text: text)
            store.mergeMessages([message], into: conversationID)
            store.setLastMessage(message, in: conversationID)
            persist(operation: "send-message") { try database.upsertConversationMessages([message], conversationID: conversationID) }
            persistConversation(conversationID)
            return true
        } catch {
            logger.error("Failed to send conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to send conversation message")
            return false
        }
    }

    /// Debounced read-pointer advance: collapses a burst of arrivals into a
    /// single `markRead` round-trip ~400ms after the last one, instead of one
    /// RPC per incoming message.
    func scheduleMarkRead(conversationID: ConversationID) {
        markReadTasks[conversationID]?.cancel()
        markReadTasks[conversationID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.markRead(conversationID: conversationID)
        }
    }

    func markRead(conversationID: ConversationID) async {
        guard let latest = store.messages(for: conversationID).last else { return }
        // Skip the round-trip when the server-known READ watermark already covers
        // the latest message. We advance the watermark locally after each success.
        if let read = store.selfReadPointer(for: conversationID, selfUserID: selfUserID), latest.id <= read {
            return
        }
        do {
            try await messaging.markRead(owner: owner, conversationID: conversationID, messageID: latest.id)
            store.advanceSelfReadPointer(to: latest.id, in: conversationID, selfUserID: selfUserID)
            persistConversation(conversationID)
        } catch {
            logger.error("Failed to mark conversation read", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to mark conversation read")
        }
    }
}
