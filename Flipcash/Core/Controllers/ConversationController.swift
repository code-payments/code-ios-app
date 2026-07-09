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

    /// The `stableID` of a just-sent optimistic message whose receipt is currently held back so it can
    /// cross-fade onto a settled bubble; the transcript mapping suppresses that row's receipt while set.
    var settlingSendID: String? { receiptSettle.settlingID }

    /// The conversation with this ID, if the feed currently holds it.
    func conversation(withID id: ConversationID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Number of conversations with unread messages for the signed-in user.
    var unreadConversationCount: Int {
        conversations.filter { $0.hasUnread(for: selfUserID) }.count
    }

    /// The signed-in user, used to tell own messages from the counterpart's.
    let selfUserID: UserID

    /// The conversation currently on screen, set by `ConversationScreen` while
    /// it's visible and cleared when it leaves. Read by the push delegate to
    /// suppress foreground banners for the open chat; never drives a view, so
    /// it's excluded from observation.
    @ObservationIgnored var visibleConversationID: ConversationID?

    private var store = ConversationStore()

    @ObservationIgnored private let fetching: any ConversationFetching
    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let streaming: any ConversationEventStreaming
    @ObservationIgnored private let contactNaming: any DMContactNaming
    @ObservationIgnored private let database: Database
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var connectionStateTask: Task<Void, Never>?
    /// Whether the event stream has been seen `.live` at least once. The first
    /// `.live` is the initial connection (the feed/transcript are already loaded
    /// by `start()` and the screen), so it's skipped; every `.live` after it is a
    /// reconnect whose missed window needs refetching.
    @ObservationIgnored private var hasSeenStreamLive = false
    @ObservationIgnored private var hydratingConversationIDs: Set<ConversationID> = []
    @ObservationIgnored private var markReadTasks: [ConversationID: Task<Void, Never>] = [:]
    /// Conversations with a `GetDelta` catch-up in flight. Dedups overlapping triggers (foreground +
    /// a near-simultaneous reconnect, or a gap-fill racing a reconnect) so two streams don't apply
    /// checkpoints out of order and regress the frontier.
    @ObservationIgnored private var catchUpInFlight: Set<ConversationID> = []
    /// Debounced live-gap catch-ups, one per conversation: a detected gap waits briefly (a late
    /// out-of-order event may close it) before spending a `GetDelta`.
    @ObservationIgnored private var gapCatchUpTasks: [ConversationID: Task<Void, Never>] = [:]
    @ObservationIgnored private let receiptSettle = ReceiptSettleGate()

    /// The typing-indicator concern, both directions (outgoing driver + incoming typist
    /// tracking), owned by its own unit. Reads chain through `@Observable` tracking.
    private let typing: ConversationTyping

    init(
        fetching: any ConversationFetching,
        messaging: any ConversationMessaging,
        streaming: any ConversationEventStreaming,
        contactNaming: any DMContactNaming,
        database: Database,
        owner: KeyPair,
        selfUserID: UserID,
        typingHeartbeatInterval: Duration = .seconds(3),
        typingTimeout: Duration = .seconds(5),
        incomingTypingExpiry: Duration = .seconds(10)
    ) {
        self.fetching = fetching
        self.messaging = messaging
        self.streaming = streaming
        self.contactNaming = contactNaming
        self.database = database
        self.owner = owner
        self.selfUserID = selfUserID
        self.typing = ConversationTyping(
            messaging: messaging,
            owner: owner,
            selfUserID: selfUserID,
            heartbeatInterval: typingHeartbeatInterval,
            timeout: typingTimeout,
            incomingExpiry: incomingTypingExpiry
        )
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
                store.seedAppliedCursors(cache.cursors)
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
            observeConnectionState()
            await loadFeed()
        }
    }

    private func openStream() {
        guard streamTask == nil else { return }
        let events = streaming.openConversationStream(owner: owner)
        streamTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                let gap = self.store.apply(event)
                self.persist(event: event)
                self.hydrateIfUnknown(event)
                self.logCounterpartRead(event)
                self.applyTyping(event)
                if case .needsCatchUp(let conversationID, _) = gap {
                    self.scheduleGapCatchUp(conversationID)
                }
            }
        }
    }

    /// A reconnect can miss live events while the stream was down; the event log carries a per-chat
    /// cursor, so on reconnect we reconcile the missed window from that cursor via `GetDelta`. The first
    /// `.live` is the initial connection (already loaded by `start()`/the screen); every `.live` after
    /// it is a reconnect. This edge is a belt-and-suspenders trigger — foreground, chat-open, and a
    /// detected live gap already drive catch-up without waiting for a ping.
    private func observeConnectionState() {
        guard connectionStateTask == nil else { return }
        let states = streaming.conversationConnectionState()
        connectionStateTask = Task { [weak self] in
            for await state in states {
                guard let self else { return }
                guard state == .live else { continue }
                if self.hasSeenStreamLive {
                    await self.refetchAfterReconnect()
                } else {
                    self.hasSeenStreamLive = true
                }
            }
        }
    }

    private func refetchAfterReconnect() async {
        logger.info("Stream reconnected, catching up the missed window", metadata: [
            "visibleConversation": visibleConversationID.map { "\($0)" } ?? "none",
        ])
        // Refresh the feed (unread + head truth) and reconcile the open transcript from the event-log
        // cursor via GetDelta — not a blind newest-page reload. Both are @MainActor (store mutations
        // stay serial) but their network calls run off-main, so overlap them rather than awaiting in
        // series.
        async let feed: Void = loadFeed()
        if let visibleConversationID {
            await catchUp(conversationID: visibleConversationID)
        }
        await feed
    }

    // MARK: - Event-log catch-up

    /// Reconcile a conversation's transcript from its persisted event-log cursor via `GetDelta`,
    /// applying and persisting each batch's checkpoint as it arrives. Deduped per conversation — a
    /// second caller while one is in flight no-ops. Fired on chat-open, foreground, reconnect, and a
    /// detected live gap; none of these wait for a server ping.
    func catchUp(conversationID: ConversationID) async {
        guard !catchUpInFlight.contains(conversationID) else { return }
        catchUpInFlight.insert(conversationID)
        defer { catchUpInFlight.remove(conversationID) }

        let after = store.appliedCursor(for: conversationID)
        do {
            let head = try await messaging.getDelta(owner: owner, conversationID: conversationID, afterSequence: after) { [weak self] messages, checkpoint in
                guard let self else { return }
                self.store.applyDeltaBatch(messages, checkpoint: checkpoint, into: conversationID)
                if !messages.isEmpty {
                    self.persist(operation: "delta-batch") { try self.database.upsertConversationMessages(messages, conversationID: conversationID) }
                }
                self.persistCursor(for: conversationID)
            }
            // Clean completion: the head is authoritative even if the intervening events weren't observed.
            store.setAppliedCursor(head, for: conversationID)
            persistCursor(for: conversationID)
            // `after` vs `head`: equal means already current; a jump means the delta window that was
            // caught up. Observable so the production catch-up cadence can be traced.
            logger.info("Chat catch-up complete", metadata: [
                "conversationID": "\(conversationID)",
                "after": "\(after)",
                "head": "\(head)",
            ])
        } catch let error as ErrorGetDelta where error == .resetRequired {
            await resyncAfterReset(conversationID: conversationID)
        } catch {
            // Transport / denied / unknown: leave the cursor at the last persisted checkpoint so the
            // next trigger resumes from there. captureError classifies transient failures as suppressed.
            logger.error("Chat catch-up failed", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Chat delta catch-up failed")
        }
    }

    /// Foreground hook (`AppDelegate` `.active`): reconcile the on-screen chat regardless of any ping.
    func catchUpOpenChat() {
        guard let visibleConversationID else { return }
        Task { await catchUp(conversationID: visibleConversationID) }
    }

    /// A live event exposed a gap. Debounce briefly — a late out-of-order event may close it before we
    /// spend a round trip — then reconcile from the (possibly already-advanced) cursor.
    private func scheduleGapCatchUp(_ conversationID: ConversationID) {
        gapCatchUpTasks[conversationID]?.cancel()
        gapCatchUpTasks[conversationID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.catchUp(conversationID: conversationID)
        }
    }

    /// `RESET_REQUIRED`: the cursor is too far behind to stream a delta. Discard it, re-sync the newest
    /// page via `GetMessages`, and seat the cursor to that page's lowest event sequence — a safe floor
    /// the next catch-up backfills from, never the head (which would skip the un-loaded window).
    private func resyncAfterReset(conversationID: ConversationID) async {
        logger.info("Chat catch-up reset required, re-syncing history", metadata: ["conversationID": "\(conversationID)"])
        store.resetCursor(for: conversationID)
        // Persist the reset now (persistCursor won't write 0): if the re-sync below throws, the stale
        // too-far-behind cursor must not survive to the next launch and immediately re-hit RESET_REQUIRED.
        persist(operation: "reset-cursor") { try database.updateCatchupCursor(0, for: conversationID) }
        do {
            let messages = try await messaging.getMessages(owner: owner, conversationID: conversationID, before: nil)
            store.mergeMessages(messages, into: conversationID)
            persist(operation: "reset-resync") { try database.upsertConversationMessages(messages, conversationID: conversationID) }
            if let floor = messages.map(\.eventSequence).filter({ $0 > 0 }).min() {
                store.setAppliedCursor(floor, for: conversationID)
                persistCursor(for: conversationID)
            }
        } catch {
            logger.error("Failed to re-sync after catch-up reset", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to re-sync after chat catch-up reset")
        }
    }

    /// Persist the store's current catch-up frontier (no-op until one is established).
    private func persistCursor(for conversationID: ConversationID) {
        let cursor = store.appliedCursor(for: conversationID)
        guard cursor > 0 else { return }
        persist(operation: "update-cursor") { try database.updateCatchupCursor(cursor, for: conversationID) }
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

    /// Routes a live typing event to the typing unit.
    private func applyTyping(_ event: ConversationStreamEvent) {
        guard case .typingChanged(let conversationID, let notifications) = event else { return }
        typing.apply(notifications, in: conversationID)
    }

    /// Whether any OTHER member is currently typing in this conversation.
    func isCounterpartTyping(in conversationID: ConversationID) -> Bool {
        typing.isCounterpartTyping(in: conversationID)
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        streamTask?.cancel()
        streamTask = nil
        connectionStateTask?.cancel()
        connectionStateTask = nil
        markReadTasks.values.forEach { $0.cancel() }
        markReadTasks.removeAll()
        gapCatchUpTasks.values.forEach { $0.cancel() }
        gapCatchUpTasks.removeAll()
        catchUpInFlight.removeAll()
        typing.stop()
        receiptSettle.cancel()
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
        case .newMessages(let id, _), .chatEvents(let id, _), .lastActivityChanged(let id, _), .readPointersChanged(let id, _):
            conversationID = id
        case .metadataRefresh:
            return
        case .typingChanged:
            // A typing event for an unknown conversation isn't worth a metadata fetch — it's transient.
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
        case .chatEvents(let conversationID, let events):
            let messages = events.flatMap { $0.mutations.map(\.message) }
            if !messages.isEmpty {
                persist(operation: "upsert-events") { try database.upsertConversationMessages(messages, conversationID: conversationID) }
            }
            persistCursor(for: conversationID)
            persistConversation(conversationID)
        case .metadataRefresh(let conversation):
            persistConversation(conversation)
        case .lastActivityChanged(let conversationID, _),
             .readPointersChanged(let conversationID, _):
            persistConversation(conversationID)
        case .typingChanged:
            break
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

    /// Counterpart name shown when neither the synced contacts, the feed, nor a
    /// shared phone number provides one.
    static let fallbackCounterpartName = "Flipcash User"

    /// The counterpart's name for a conversation: the synced contact's
    /// address-book name, else the server-provided member name from the feed,
    /// else the counterpart's shared phone number, else a generic fallback.
    func displayName(for conversation: Conversation) -> String {
        if let contactName = contactName(for: conversation.id) {
            return contactName
        }
        guard let counterpart = conversation.counterpart(excluding: selfUserID) else {
            return Self.fallbackCounterpartName
        }
        if !counterpart.displayName.isEmpty {
            return counterpart.displayName
        }
        return counterpart.formattedPhoneNumber ?? Self.fallbackCounterpartName
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
        store.displayedMessages(for: conversationID)
    }

    /// The newest server-confirmed message — what the screen's receive buzz and mark-read track, so an
    /// unresolved optimistic send (which renders after the confirmed run) never masks an incoming one.
    func lastConfirmedMessage(for conversationID: ConversationID) -> ConversationMessage? {
        store.lastConfirmedMessage(for: conversationID)
    }

    /// Whether the conversation holds any message, without building the merged transcript.
    func hasMessages(for conversationID: ConversationID) -> Bool {
        store.hasMessages(for: conversationID)
    }

    func loadMessages(for conversationID: ConversationID) async {
        do {
            let messages = try await messaging.getMessages(owner: owner, conversationID: conversationID, before: nil)
            logger.info("Loaded conversation messages", metadata: [
                "conversationID": "\(conversationID)",
                "count": "\(messages.count)",
            ])
            store.mergeMessages(messages, into: conversationID)
            // Establish the event-log frontier from the newest page so a following catch-up resumes from
            // head — fetching only genuinely newer messages, appended at the tail — instead of a
            // `GetDelta(after: 0)` that re-pulls the whole history and prepends it, knocking the
            // transcript off the bottom on first open.
            if let head = messages.map(\.eventSequence).max(), head > 0 {
                store.setAppliedCursor(head, for: conversationID)
                persistCursor(for: conversationID)
            }
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

    /// Optimistically inserts the message so it appears instantly as `.sending`, then awaits the
    /// server: on success it reconciles to the confirmed message, on failure it stays in the
    /// transcript as `.failed` (never silently dropped).
    @discardableResult
    func send(_ text: String, to conversationID: ConversationID) async -> Bool {
        let clientMessageID = UUID()
        let pending = ConversationMessage(
            id: .unassigned,
            senderID: selfUserID,
            content: .text(text),
            date: .now,
            unreadSeq: 0,
            status: .sending,
            clientMessageID: clientMessageID
        )
        store.insertPending(pending, into: conversationID)
        receiptSettle.hold(clientMessageID.uuidString)
        return await deliver(clientMessageID: clientMessageID, text: text, to: conversationID)
    }

    /// Re-send a failed optimistic message, reusing its client id so the server (idempotent on it)
    /// returns the original message rather than creating a duplicate. Only a `.failed` row is retried,
    /// so a double-tap (or a tap during a slow in-flight retry) can't fire concurrent sends.
    func retry(clientMessageID: UUID, in conversationID: ConversationID) async {
        guard let pending = store.pendingMessage(clientMessageID: clientMessageID, in: conversationID),
              pending.status == .failed,
              case .text(let text) = pending.content else { return }
        store.markPending(clientMessageID: clientMessageID, status: .sending, in: conversationID)
        _ = await deliver(clientMessageID: clientMessageID, text: text, to: conversationID)
    }

    private func deliver(clientMessageID: UUID, text: String, to conversationID: ConversationID) async -> Bool {
        do {
            let message = try await messaging.sendMessage(owner: owner, conversationID: conversationID, text: text, clientMessageID: clientMessageID)
            store.reconcile(clientMessageID: clientMessageID, with: message, in: conversationID)
            store.setLastMessage(message, in: conversationID)
            persist(operation: "send-message") { try database.upsertConversationMessages([message], conversationID: conversationID) }
            persistConversation(conversationID)
            Analytics.track(event: Analytics.ConversationEvent.sentMessage)
            return true
        } catch {
            store.markPending(clientMessageID: clientMessageID, status: .failed, in: conversationID)
            logger.error("Failed to send conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to send conversation message")
            Analytics.track(event: Analytics.ConversationEvent.sentMessage, error: error)
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

    // MARK: - Outgoing typing

    /// Drives outgoing typing from the composer's draft; see `ConversationTyping`.
    func draftDidChange(_ text: String, in conversationID: ConversationID) {
        typing.draftDidChange(text, in: conversationID)
    }

    /// Force-stop outgoing typing (draft cleared, message sent, or the composer lost focus).
    func stopSelfTyping(in conversationID: ConversationID) {
        typing.stopSelfTyping(in: conversationID)
    }
}
