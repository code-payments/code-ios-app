//
//  ConversationController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import os
import SwiftUI
import FlipcashCore
import FlipcashStore

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

    /// Whether the feed's contents are known: seeded from a non-empty cache, or answered by the
    /// server once. Until then an empty feed means not yet loaded, not no chats.
    private(set) var hasResolvedFeed = false

    /// The `stableID` of a just-sent optimistic message whose receipt is currently held back so it can
    /// cross-fade onto a settled bubble; the transcript mapping suppresses that row's receipt while set.
    var settlingSendID: String? { receiptSettle.settlingID }

    /// The conversation with this ID, if the feed currently holds it.
    func conversation(withID id: ConversationID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// The visible feed, excluding hidden (blocked-counterpart) conversations.
    var visibleConversations: [Conversation] { conversations.filter { !$0.isHidden } }

    /// DM conversations of `type`, most-recent activity first, excluding hidden conversations.
    func conversations(of type: ConversationType) -> [Conversation] {
        conversations.filter { $0.type == type && !$0.isHidden }
    }

    /// Reconciles every conversation's hidden flag against the authoritative
    /// blocklist so a blocked counterpart's chat drops from the feed and an
    /// unblocked one returns; re-run after each feed load and on any blocklist change.
    func reconcileHidden() {
        let blocked = blockedUserIDs()
        for conversation in store.conversations {
            // `counterpart(excluding:)` picks an arbitrary member of a group, so one blocked member
            // would hide the whole chat from the feed — and this runs after every DM feed load, so a
            // group the feed never touched would vanish. Blocking is a DM relationship.
            guard conversation.type != .group else {
                if conversation.isHidden { store.setHidden(false, in: conversation.id) }
                continue
            }
            let hidden = conversation.counterpart(excluding: selfUserID)?.userID.map(blocked.contains) ?? false
            if conversation.isHidden != hidden {
                store.setHidden(hidden, in: conversation.id)
                // Blocking someone drops the draft aimed at them along with their chat.
                if hidden { chatDrafts?.remove(for: conversation.id) }
            }
        }
    }

    /// The chats the Chats tab lists, newest activity first: tip DMs and the groups the user has joined.
    var chatListConversations: [Conversation] {
        (conversations(of: .tipDm) + joinedGroups)
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Number of ``chatListConversations`` with unread messages for the signed-in user.
    var unreadChatListCount: Int {
        chatListConversations.count { $0.hasUnread(for: selfUserID) }
    }

    /// The unread count a conversation row shows; nil when the chat is unread but its READ
    /// watermark's message is neither stored nor fetched yet. See
    /// ``Conversation/unreadCount(for:unreadSeqAt:)`` and ``resolveUnreadCount(for:)``.
    func unreadCount(for conversation: Conversation) -> Int? {
        conversation.unreadCount(for: selfUserID) { pointer in
            storedUnreadSeq(of: pointer, in: conversation.id)
                ?? watermarkStamps.stamp(for: .init(conversationID: conversation.id, messageID: pointer))
        }
    }

    /// Fetches the READ watermark's message when ``unreadCount(for:)`` can't be known without it,
    /// so the row's count fills in. A no-op for a chat whose count is already known.
    func resolveUnreadCount(for conversation: Conversation) async {
        guard unreadCount(for: conversation) == nil,
              let pointer = conversation.selfReadPointer(for: selfUserID),
              storedUnreadSeq(of: pointer, in: conversation.id) == nil
        else { return }
        do {
            try await watermarkStamps.resolve(.init(conversationID: conversation.id, messageID: pointer)) {
                try await messaging.getMessage(owner: owner, conversationID: conversation.id, messageID: pointer)
            }
        } catch {
            logger.error("Failed to fetch the READ watermark's message", metadata: [
                "conversationID": "\(conversation.id)",
                "messageID": "\(pointer.value)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to fetch the READ watermark's message")
        }
    }

    /// The `unreadSeq` of a message this device stores.
    private func storedUnreadSeq(of messageID: MessageID, in conversationID: ConversationID) -> UInt64? {
        _ = messageRevision   // observe: the watermark's message can land after the row draws
        return ((try? database.message(id: messageID, conversationID: conversationID)) ?? nil)?.unreadSeq
    }

    /// The conversation for an id, hydrating it from the server when the feed
    /// doesn't hold it yet — the same fetch + apply + persist path stream
    /// events use, so the caller's screen finds the chat populated. Returns
    /// nil when the server doesn't know the chat either.
    func hydratedConversation(withID conversationID: ConversationID) async -> Conversation? {
        if let conversation = conversation(withID: conversationID) {
            return conversation
        }
        do {
            let conversation = try await fetching.getChat(owner: owner, conversationID: conversationID)
            store.apply(.metadataRefresh(conversation))
            // The server copy, not the store's: the store drops a tombstone preview, and the
            // database wants the row so the repair below can tell the newest message was deleted.
            persistConversation(conversation)
            refreshFeedPreview(for: conversationID)
            return conversation
        } catch {
            logger.error("Failed to hydrate conversation on demand", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to hydrate conversation on demand")
            return nil
        }
    }

    /// The signed-in user, used to tell own messages from the counterpart's.
    let selfUserID: UserID

    /// The conversation currently on screen, set by `ConversationScreen` while
    /// it's visible and cleared when it leaves. Read by the push delegate to
    /// suppress foreground banners for the open chat; never drives a view, so
    /// it's excluded from observation.
    @ObservationIgnored var visibleConversationID: ConversationID?

    var store: ConversationStore

    /// The current blocklist (wired to `BlocklistController`), used to reconcile
    /// which conversations are hidden from the feed.
    @ObservationIgnored var blockedUserIDs: () -> Set<UserID> = { [] }

    /// A conversation's participation rules weighed against the signed-in user — wired to
    /// ``conversationGate(session:rules:rates:)`` at session setup. The default gates nothing,
    /// which is right for every DM and for a group with no rules.
    @ObservationIgnored var gateConversation: (Conversation) -> ConversationGate = { _ in .open }

    /// Whether the transcript for `conversationID` is worth a round trip: the same line the screen's
    /// blur draws, so nothing is fetched that the screen would cover and nothing it shows goes
    /// unfetched. `GetMessages` and `GetDelta` answer `DENIED` to anyone the gate obscures — a
    /// viewer short of the listener rules, and a non-member of a group that states none. A
    /// conversation the feed doesn't hold yet is assumed readable: its rules aren't known, and
    /// refusing to fetch would leave it permanently empty.
    private func canRead(_ conversationID: ConversationID) -> Bool {
        guard let conversation = conversation(withID: conversationID) else { return true }
        let presentation = conversationGatePresentation(
            gateConversation(conversation),
            isMember: store.isMember(of: conversation)
        )
        return !presentation.obscuresTranscript
    }

    /// Whether the user's read pointer in `conversationID` can move. `AdvancePointer` is a member's
    /// write, so an eligible non-member reads the transcript without marking it read.
    private func canAdvancePointer(_ conversationID: ConversationID) -> Bool {
        guard canRead(conversationID) else { return false }
        guard let conversation = conversation(withID: conversationID) else { return true }
        return store.isMember(of: conversation)
    }

    @ObservationIgnored private let fetching: any ConversationFetching
    @ObservationIgnored private let membership: any ConversationMembership
    @ObservationIgnored private let viewerSettings: any ConversationViewerSettings
    @ObservationIgnored let messaging: any ConversationMessaging
    @ObservationIgnored private let streaming: any ConversationEventStreaming
    @ObservationIgnored private let contactNaming: any DMContactNaming
    @ObservationIgnored let database: Database
    @ObservationIgnored let owner: KeyPair
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// The cache read's result, held for `hydrateIfReady()`; set off the main actor.
    @ObservationIgnored private let finishedCache = OSAllocatedUnfairLock<ConversationCache?>(initialState: nil)
    @ObservationIgnored private var hasAppliedCache = false
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var connectionStateTask: Task<Void, Never>?
    /// Whether the event stream has been seen `.live` at least once. The first
    /// `.live` is the initial connection (the feed/transcript are already loaded
    /// by `start()` and the screen), so it's skipped; every `.live` after it is a
    /// reconnect whose missed window needs refetching.
    @ObservationIgnored private var hasSeenStreamLive = false
    @ObservationIgnored private var hydratingConversationIDs: Set<ConversationID> = []
    /// The in-flight `AdvancePointer` send per conversation — see ``syncReadPointer(in:)``.
    @ObservationIgnored private(set) var readPointerSyncTasks: [ConversationID: Task<Void, Never>] = [:]
    /// Conversations with a `GetDelta` catch-up in flight. Dedups overlapping triggers (foreground +
    /// a near-simultaneous reconnect, or a gap-fill racing a reconnect) so two streams don't apply
    /// checkpoints out of order and regress the frontier.
    @ObservationIgnored private var catchUpInFlight: Set<ConversationID> = []
    /// Debounced live-gap catch-ups, one per conversation: a detected gap waits briefly (a late
    /// out-of-order event may close it) before spending a `GetDelta`.
    @ObservationIgnored private var gapCatchUpTasks: [ConversationID: Task<Void, Never>] = [:]
    /// Conversations with a newest-page `GetMessages` in flight. Read by the backfill so it doesn't
    /// re-fetch a page the open chat is already loading; `loadMessages` itself never short-circuits,
    /// because the opening screen awaits the fresh page it returns.
    @ObservationIgnored private var messageLoadsInFlight: Set<ConversationID> = []
    @ObservationIgnored private let receiptSettle = ReceiptSettleGate()
    @ObservationIgnored private let watermarkStamps = ReadWatermarkStamps()

    /// The session's chat drafts, wired by `SessionContainer` after construction — the controller
    /// is built before the container has finished assembling, and the tests build it without one.
    @ObservationIgnored var chatDrafts: ChatDraftStore? {
        didSet { failedSends = chatDrafts.map(FailedSendDrafts.init(store:)) }
    }

    /// Keeps the words of a send that failed — see ``FailedSendDrafts``.
    @ObservationIgnored private var failedSends: FailedSendDrafts?
    /// The receive-side analytics concern (cumulative counters + received events),
    /// owned by its own unit. Exposed so `SessionContainer` can wire its rate lookup.
    @ObservationIgnored let receipts: ConversationReceiptReporter

    /// The typing-indicator concern, both directions (outgoing driver + incoming typist
    /// tracking), owned by its own unit. Reads chain through `@Observable` tracking.
    /// The typing indicators for the user's conversations.
    private let typing: ConversationTyping

    /// The emoji reactions concern: the user's taps, their calls, and the stream's updates.
    let reactions: ConversationReactions

    init(
        fetching: any ConversationFetching,
        membership: any ConversationMembership,
        viewerSettings: any ConversationViewerSettings,
        messaging: any ConversationMessaging,
        streaming: any ConversationEventStreaming,
        contactNaming: any DMContactNaming,
        database: Database,
        owner: KeyPair,
        selfUserID: UserID,
        typingHeartbeatInterval: Duration = .seconds(3),
        typingTimeout: Duration = .seconds(5),
        incomingTypingExpiry: Duration = .seconds(10),
        typingExpiryClock: TypingExpiryClock = .continuous,
        receipts: ConversationReceiptReporter? = nil
    ) {
        self.fetching = fetching
        self.membership = membership
        self.viewerSettings = viewerSettings
        self.messaging = messaging
        self.streaming = streaming
        self.contactNaming = contactNaming
        self.database = database
        self.owner = owner
        self.selfUserID = selfUserID
        self.store = ConversationStore(selfUserID: selfUserID)
        self.receipts = receipts ?? ConversationReceiptReporter(selfUserID: selfUserID)
        self.typing = ConversationTyping(
            messaging: messaging,
            owner: owner,
            selfUserID: selfUserID,
            heartbeatInterval: typingHeartbeatInterval,
            timeout: typingTimeout,
            incomingExpiry: incomingTypingExpiry,
            expiryClock: typingExpiryClock
        )
        self.reactions = ConversationReactions(
            messaging: messaging,
            database: database,
            owner: owner,
            selfUserID: selfUserID
        )
        reactions.didPersist = { [weak self] in self?.bumpMessageRevision() }
    }

    /// Seeds the store from the local cache so the feed, unread state, and
    /// transcripts render without a network round-trip. The merge is
    /// animation-suppressed so on-screen surfaces don't play insertion
    /// transitions for cached history.
    func hydrateFromDatabase() async {
        await hydrateFromDatabase(loading: loadCache(), unlessApplied: false)
    }

    /// Seeds the store from the cache read `start()` began, if that read has already finished. Never
    /// waits on it. Lets a screen that is about to draw take the cache in the same frame, rather than
    /// after the main actor has worked through the rest of launch.
    func hydrateIfReady() {
        guard !hasAppliedCache, let cache = finishedCache.withLock({ $0 }) else { return }
        applyCache(cache)
    }

    private typealias ConversationCache = (conversations: [Conversation], cursors: [ConversationID: UInt64], joinedGroups: Set<ConversationID>)

    /// Starts the cache read off the main actor, so it doesn't wait for the main thread to come free.
    private func loadCache() -> Task<ConversationCache, Error> {
        Task.detached { [database, finishedCache] in
            let cache = try await database.loadConversationCache()
            finishedCache.withLock { $0 = cache }
            return cache
        }
    }

    /// `unlessApplied` skips a cache `hydrateIfReady()` already took, so launch doesn't apply it twice.
    private func hydrateFromDatabase(loading load: Task<ConversationCache, Error>, unlessApplied: Bool) async {
        do {
            let cache = try await load.value
            if unlessApplied, hasAppliedCache { return }
            applyCache(cache)
        } catch {
            logger.error("Failed to load conversation cache", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to load conversation cache")
        }
    }

    private func applyCache(_ cache: ConversationCache) {
        hasAppliedCache = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // Memberships seed ahead of the feed guard: they live in their own table, and a group
            // the user has joined must not sit blurred behind its own gate for as long as the group
            // feed takes to land — or for the whole session, offline.
            store.seedMemberships(cache.joinedGroups)
            guard !cache.conversations.isEmpty else { return }
            store.setFeed(cache.conversations)
            store.seedAppliedCursors(cache.cursors)
        }
        // An empty cache proves nothing — a fresh login has one — so that case waits for the feed.
        if !cache.conversations.isEmpty {
            hasResolvedFeed = true
        }
    }

    // MARK: - Lifecycle

    /// Hydrates from the local cache, opens the event stream, then loads the
    /// feed — in that order so live events aren't lost mid-load. Idempotent.
    func start() {
        guard startTask == nil else { return }
        // The read starts here rather than inside the task: at launch the main actor is busy building
        // the tab UI, and a read queued behind that lands after the Chats tab has drawn empty. The
        // Chats screen picks the result up through `hydrateIfReady()` as it appears.
        let cache = loadCache()
        startTask = Task {
            await hydrateFromDatabase(loading: cache, unlessApplied: true)
            await openStream()
            await loadFeed()
        }
    }

    private func openStream() async {
        guard streamTask == nil else { return }
        // Subscribe once for a fresh event + connection-state stream pair (the streamer is an
        // app-lifetime singleton that vends a new pair per session, so a switched-to account isn't
        // stranded on the previous session's dead stream). Wire both loops before the feed loads so no
        // live event is lost mid-load.
        let (events, states) = await streaming.subscribeConversationStream(owner: owner)
        streamTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                let gap = self.store.apply(event)
                self.persist(event: event)
                // Before `hydrateIfUnknown`: the user's own join carries the chat's metadata, so
                // seating it here spares a `GetChat` for a group the feed hasn't reached yet.
                self.applyRosterMembership(event)
                self.hydrateIfUnknown(event)
                self.logCounterpartRead(event)
                self.applyTyping(event)
                self.applyReactions(event)
                if case .needsCatchUp(let conversationID, _) = gap {
                    self.scheduleGapCatchUp(conversationID)
                }
            }
        }
        observeConnectionState(states)
    }

    /// A reconnect can miss live events while the stream was down; the event log carries a per-chat
    /// cursor, so on reconnect we reconcile the missed window from that cursor via `GetDelta`. The first
    /// `.live` is the initial connection (already loaded by `start()`/the screen); every `.live` after
    /// it is a reconnect. This edge is a belt-and-suspenders trigger — foreground, chat-open, and a
    /// detected live gap already drive catch-up without waiting for a ping. Consumes the same
    /// subscription's connection-state stream opened by `openStream()`.
    private func observeConnectionState(_ states: AsyncStream<EventStreamConnectionState>) {
        guard connectionStateTask == nil else { return }
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
    /// detected live gap; none of these wait for a server ping. No-ops for a conversation the client
    /// holds nothing for — no feed entry, no messages, no applied cursor.
    func catchUp(conversationID: ConversationID) async {
        guard conversation(withID: conversationID) != nil
            || hasMessages(for: conversationID)
            || store.appliedCursor(for: conversationID) > 0 else {
            logger.info("Skipping catch-up for a conversation the client holds nothing for", metadata: [
                "conversationID": "\(conversationID)",
            ])
            return
        }
        guard canRead(conversationID) else {
            logger.info("Skipping catch-up for a conversation the user may not read", metadata: [
                "conversationID": "\(conversationID)",
            ])
            return
        }
        guard !catchUpInFlight.contains(conversationID) else { return }
        catchUpInFlight.insert(conversationID)
        defer { catchUpInFlight.remove(conversationID) }

        let after = store.appliedCursor(for: conversationID)
        // One baseline for the whole run. A per-batch watermark would let the second
        // batch of a cold backfill count everything the first batch just seeded.
        let countedThrough = (try? database.newestMessageID(conversationID: conversationID)) ?? nil
        do {
            var anyBatchFailed = false
            let head = try await messaging.getDelta(owner: owner, conversationID: conversationID, afterSequence: after) { [weak self] messages, checkpoint in
                guard let self else { return }
                let (reconciled, pairs) = self.reconciledForPersist(messages, in: conversationID)
                // Batch + checkpoint cursor persist atomically; advance the in-memory checkpoint only
                // after the write succeeds, so a rolled-back batch isn't skipped on the next catch-up.
                let cursor = checkpoint ?? self.store.appliedCursor(for: conversationID)
                let ok = self.persist(operation: "delta-batch") {
                    try self.database.persistMessages(reconciled, cursor: cursor, conversationID: conversationID)
                }
                if ok {
                    self.commitReconciled(pairs, in: conversationID)
                    self.receipts.countReceived(reconciled, countedThrough: countedThrough, delivery: .catchUp)
                    if let checkpoint { self.store.setAppliedCursor(checkpoint, for: conversationID) }
                } else {
                    anyBatchFailed = true
                }
                self.refreshFeedPreview(for: conversationID)
            }
            // Clean completion: the head is authoritative — but only when every batch landed. Seating
            // head over a rolled-back batch would orphan its messages from every future GetDelta.
            if anyBatchFailed {
                store.reseatCursor((try? database.catchupCursor(conversationID: conversationID)) ?? 0, for: conversationID)
                scheduleGapCatchUp(conversationID)
            } else {
                store.setAppliedCursor(head, for: conversationID)
                persistCursor(for: conversationID)
            }
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
        Task {
            await catchUp(conversationID: visibleConversationID)
            await refreshReactions(for: visibleConversationID)
        }
    }

    /// Refreshes from the server the reactions on up to `limit` stored messages older than `before`,
    /// or the newest when `before` is nil: one page of the transcript as the reader reveals it.
    func refreshReactions(for conversationID: ConversationID, before: UInt64? = nil, limit: Int = MessageLoader.initialWindow) async {
        guard canRead(conversationID) else { return }
        let messageIDs: [MessageID]
        do {
            messageIDs = try database.messageIDs(conversationID: conversationID, before: before, limit: min(limit, Self.reactionRefreshLimit))
        } catch {
            logger.error("Failed to read message ids for a reaction refresh", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to read message ids for a reaction refresh")
            return
        }
        await reactions.refresh(messageIDs, in: conversationID)
    }

    /// The most messages one `GetReactionSummaries` call takes.
    private static let reactionRefreshLimit = 100

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
            let (reconciled, pairs) = reconciledForPersist(messages, in: conversationID)
            let floor = messages.map(\.eventSequence).filter({ $0 > 0 }).min() ?? 0
            // Page + floor cursor land atomically (a failed write must not seat the cursor), and a
            // non-overlapping page drops the stale older epoch first.
            let ok = persist(operation: "reset-resync") {
                try dropStaleEpochIfNeeded(before: messages, in: conversationID)
                try database.persistMessages(reconciled, cursor: floor, conversationID: conversationID)
            }
            if ok {
                commitReconciled(pairs, in: conversationID)
                if floor > 0 { store.setAppliedCursor(floor, for: conversationID) }
            }
            refreshFeedPreview(for: conversationID)
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

    private func applyTyping(_ event: ConversationStreamEvent) {
        guard case .typingChanged(let conversationID, let notifications) = event else { return }
        typing.apply(notifications, in: conversationID)
    }

    private func applyReactions(_ event: ConversationStreamEvent) {
        guard case .reactionsChanged(let conversationID, let updates) = event else { return }
        reactions.apply(updates, in: conversationID)
    }

    /// Returns whether another member is currently typing in the conversation.
    func isCounterpartTyping(in conversationID: ConversationID) -> Bool {
        typing.isCounterpartTyping(in: conversationID)
    }

    /// Returns the other members typing in the conversation, oldest to newest by when they started.
    func typists(in conversationID: ConversationID) -> [UserID] {
        typing.typists(in: conversationID)
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        streamTask?.cancel()
        streamTask = nil
        connectionStateTask?.cancel()
        connectionStateTask = nil
        readPointerSyncTasks.values.forEach { $0.cancel() }
        readPointerSyncTasks.removeAll()
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
        case .chatEvents(let id, _), .lastActivityChanged(let id, _), .readPointersChanged(let id, _):
            conversationID = id
        case .rosterChanged(let id, let updates):
            // Don't re-fetch a chat the server no longer considers us a member of: a self-leave means
            // `GetChat` can only come back denied.
            guard !updates.contains(where: { if case .left(let userID) = $0.change { userID == selfUserID } else { false } }) else {
                return
            }
            conversationID = id
        case .metadataRefresh:
            return
        case .typingChanged, .reactionsChanged:
            // Neither is worth a metadata fetch for an unknown conversation: typing is transient, and
            // reactions land on message rows that an unknown chat does not have yet.
            return
        case .viewerStateChanged:
            // Mute is the viewer's own state, and only a chat they are in can carry it — so an
            // unknown chat here means the feed hasn't landed, and the feed will bring the state
            // with it. Nothing to fetch.
            return
        case .titleChanged, .pictureChanged:
            // Only delivered to a chat's members, same reasoning as `.viewerStateChanged`: an unknown
            // chat here means the feed hasn't landed yet, and it will bring the current title/picture
            // with it. Nothing to fetch.
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
                persistConversation(conversation)
                refreshFeedPreview(for: conversationID)
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
        let loaded = await loadFeeds()
        // Outside the loading flag: the feed itself is on screen the moment the
        // conversations apply, and the transcripts fill behind it.
        await backfillMessages(for: loaded)
    }

    private func loadFeeds() async -> [Conversation] {
        isLoadingFeed = true
        defer {
            isLoadingFeed = false
            hasResolvedFeed = true
        }
        // Both DM feeds load concurrently and apply independently, so one
        // type's failure doesn't drop the other's conversations.
        async let contact = loadFeed(type: .contactDm)
        async let tip = loadFeed(type: .tipDm)
        async let groups = loadGroupFeed()
        return await contact + tip + groups
    }

    /// Loads the group feed, returning the groups the server reported — empty if the load failed or
    /// group chats are off.
    ///
    /// Deliberately not ``loadFeed(type:)``: `GetGroupChatFeed` answers only the groups the caller has
    /// *joined*. That makes it authoritative for membership, which it seats, but not for presence — a
    /// group reached by a `/chat/{id}` link and not joined is legitimately in the store and absent from
    /// this feed, so a type-scoped replace would delete it out from under its own open screen.
    @discardableResult
    func loadGroupFeed() async -> [Conversation] {
        do {
            let groups = try await fetching.getGroupChatFeed(owner: owner)
            let departed = store.setGroupFeed(groups)
            reconcileHidden()
            persist(operation: "replace-group-feed") { try database.replaceGroupFeed(groups, departed: departed) }
            resendUnsyncedReadPointers()
            // Same repair the DM feeds need: the store refuses a tombstone as a preview, so a chat whose
            // newest message is deleted seats blank without this.
            for group in groups where group.lastMessage?.isDeleted == true {
                refreshFeedPreview(for: group.id)
            }
            return groups
        } catch {
            logger.error("Failed to load group chat feed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to load group chat feed")
            return []
        }
    }

    /// Loads one DM feed type and returns the conversations the server reported,
    /// empty if the load failed.
    @discardableResult
    func loadFeed(type: ConversationType) async -> [Conversation] {
        do {
            let conversations = try await fetching.getDmChatFeed(owner: owner, type: type)
            store.setFeed(conversations, type: type)
            reconcileHidden()
            persist(operation: "replace-feed") { try database.replaceConversationFeed(conversations, type: type) }
            resendUnsyncedReadPointers()
            // The store refuses a tombstone as a preview, so a chat whose newest message is deleted
            // seats blank here. Fill it from the newest visible message already cached — the feed
            // reloads on every launch and foreground, so without this the row stays blank until the
            // transcript is opened.
            for conversation in conversations where conversation.lastMessage?.isDeleted == true {
                refreshFeedPreview(for: conversation.id)
            }
            return conversations
        } catch {
            logger.error("Failed to load conversation feed", metadata: [
                "type": "\(type)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to load conversation feed")
            return []
        }
    }

    // MARK: - Group membership

    /// Whether the signed-in user is a member of the conversation. Always true for a DM, so callers
    /// can ask it of any chat.
    func isMember(of conversation: Conversation) -> Bool {
        store.isMember(of: conversation)
    }

    /// The groups the user has joined, most-recent activity first, hidden chats excluded.
    ///
    /// The Chats list shows these rather than every group the store holds: a group reached by link and
    /// not joined is in the store so its own screen can offer the join, not so it can appear in a list
    /// the user never added it to.
    var joinedGroups: [Conversation] {
        conversations(of: .group).filter { store.isMember(of: $0) }
    }

    /// Joins a group and seats the metadata the join returns. Throws so the caller can surface the
    /// failure; nothing local moves unless the server accepted the join.
    func join(conversationID: ConversationID) async throws {
        let conversation = try await membership.joinChat(owner: owner, conversationID: conversationID)
        store.apply(.metadataRefresh(conversation))
        store.setMembership(true, in: conversationID)
        persistConversation(conversation)
        persistMembership(true, in: conversationID)
        refreshFeedPreview(for: conversationID)
    }

    /// Seats a group the signed-in user just created, so its screen and the Chats list have it
    /// without waiting for the next feed fetch.
    ///
    /// Separate from ``join(conversationID:)`` because there is nothing to join: `StartChat` returns
    /// the creator already seated, and the metadata it returns is the same shape `joinChat` gives
    /// back, so everything after the RPC is identical.
    func seatCreatedGroup(_ conversation: Conversation) {
        store.apply(.metadataRefresh(conversation))
        store.setMembership(true, in: conversation.id)
        persistConversation(conversation)
        persistMembership(true, in: conversation.id)
        refreshFeedPreview(for: conversation.id)
    }

    /// Seats the metadata `EditChat` returns for a chat the signed-in user just edited, so its
    /// profile and the Chats list show the new title or picture without waiting for anything else.
    ///
    /// Applies the two fields through the very mutators the `titleChanged` / `pictureChanged` stream
    /// events apply — deliberately, rather than `.metadataRefresh`. Two reasons, both load-bearing:
    ///
    /// - `.metadataRefresh` upserts the whole conversation, replacing the held row outright. The
    ///   edit response carries chat metadata, not the locally-held membership flag, viewer state or
    ///   roster, so a wholesale replace would drop them.
    /// - Both mutators are last-write-wins assignments, so when the server's own echo of this edit
    ///   arrives on the stream it re-applies identical values. The local apply and the echo are the
    ///   same write, which is what keeps an edit from landing twice.
    func applyEdit(_ conversation: Conversation) {
        if let title = conversation.title {
            store.applyTitleChanged(title, in: conversation.id)
        }
        if let picture = conversation.picture {
            store.applyPictureChanged(picture, in: conversation.id)
        }
        persistConversation(conversation.id)
    }

    /// Leaves a group. The chat stays in the store — the screen the user left from is still on top and
    /// needs it to render the gate — but drops out of ``joinedGroups``, so it leaves the Chats list.
    ///
    /// `notFound` counts as having left. It means the server holds no membership to remove, so the
    /// local flag is the stale one and clearing it is what reconciles the two; throwing would leave
    /// the user in a chat the server says they are not in.
    func leave(conversationID: ConversationID) async throws {
        do {
            try await membership.leaveChat(owner: owner, conversationID: conversationID)
        } catch ErrorLeaveChat.notFound {
        }
        store.setMembership(false, in: conversationID)
        persistMembership(false, in: conversationID)
        // The server clears mute on leave, so the cached state is stale the moment the leave lands.
        // Dropping it locally keeps a rejoin from showing the old mute, and discards the version
        // with it so the rejoined chat's updates aren't swallowed as stale.
        store.clearViewerState(in: conversationID)
        persistConversation(conversationID)
        chatDrafts?.remove(for: conversationID)
    }

    /// Records the signed-in user's own join or leave when a roster update names them, so a membership
    /// change made on another device reaches the gate and the chat list. Everyone else's joins and
    /// leaves are the store's business; this watches only for the user.
    ///
    /// A self-leave un-joins the chat rather than dropping it: the screen the user left from is still
    /// on top, and it needs the conversation to render the gate it just fell behind.
    private func applyRosterMembership(_ event: ConversationStreamEvent) {
        guard case .rosterChanged(let conversationID, let updates) = event else { return }
        for update in updates.sorted(by: { $0.rosterSummary.version < $1.rosterSummary.version }) {
            switch update.change {
            case .joined(let member, let chat):
                guard member.userID == selfUserID else { continue }
                if var chat {
                    // `RosterUpdate.roster_summary` is authoritative for versioning; the summary
                    // embedded in the snapshot is never compared separately, so it is overwritten.
                    chat.rosterSummary = update.rosterSummary
                    store.apply(.metadataRefresh(chat))
                    persistConversation(chat)
                }
                store.setMembership(true, in: conversationID)
                persistMembership(true, in: conversationID)
            case .left(let userID):
                guard userID == selfUserID else { continue }
                store.setMembership(false, in: conversationID)
                persistMembership(false, in: conversationID)
            }
        }
    }

    private func persistMembership(_ isMember: Bool, in conversationID: ConversationID) {
        persist(operation: "set-group-membership") {
            try database.setGroupMembership(isMember, for: conversationID)
        }
    }

    // MARK: - Mute

    /// Whether the chat is muted right now.
    ///
    /// Takes `date` so the caller can drive the recomputation: a timed mute lapses with no server
    /// signal, so there is no event to invalidate a cached answer and nothing may store one.
    func isMuted(conversationID: ConversationID, at date: Date = .now) -> Bool {
        conversation(withID: conversationID)?.isMuted(at: date) ?? false
    }

    /// Mutes a chat until `mute` lapses, or forever, seating the viewer state the server returns.
    /// Throws so the caller can surface the failure; nothing local moves unless the server accepted it.
    func mute(conversationID: ConversationID, _ mute: ConversationMuteState) async throws {
        let viewerState = try await viewerSettings.muteChat(owner: owner, conversationID: conversationID, mute: mute)
        applyViewerState(viewerState, in: conversationID)
    }

    /// Unmutes a chat. Its own RPC, not a mute of zero duration.
    func unmute(conversationID: ConversationID) async throws {
        let viewerState = try await viewerSettings.unmuteChat(owner: owner, conversationID: conversationID)
        applyViewerState(viewerState, in: conversationID)
    }

    /// Seats a viewer state the RPC returned through the same version comparison a streamed
    /// `viewerStateChanged` goes through, so a response overtaken by the stream loses rather than
    /// reinstating the state it already replaced.
    private func applyViewerState(_ viewerState: ConversationViewerState, in conversationID: ConversationID) {
        store.applyViewerStateChanged(viewerState, in: conversationID)
        persistConversation(conversationID)
    }

    // MARK: - Backfill

    /// How many conversations backfill at once. The transcripts are wanted soon, not instantly — a
    /// login with a large feed must not open a round trip per chat at the same moment as the balance,
    /// rates, and history syncs it shares the launch with.
    private static let backfillConcurrency = 4

    /// What a conversation needs to bring its local transcript level with the server.
    private enum Backfill: Equatable {
        /// The local cursor lags the server's head: stream the missed window from it.
        case delta
        /// Nothing is cached at all: fetch the newest page, which also seats the cursor to head.
        case newestPage
    }

    /// One conversation's backfill, queued.
    private struct BackfillTask: Sendable {
        let conversationID: ConversationID
        let kind: Backfill
    }

    /// Brings every conversation in a freshly-loaded feed up to the server's head, so a transcript is
    /// there when the chat is opened rather than fetched on arrival.
    ///
    /// Without this, chat history is only ever fetched by opening a chat, and each fresh login —
    /// switching accounts included — starts from a per-owner database with no messages in it at all.
    /// Ported from Android's `FeedSyncDelegate`, branch order included: a cursor that lags is streamed
    /// forward from where it sits, and only a conversation holding nothing falls back to the newest
    /// page. Reversing that would spend a `GetDelta(after: 0)` re-pulling whole histories.
    private func backfillMessages(for conversations: [Conversation]) async {
        // Deduped by id: the feed loads by type, and a conversation reported under more than one type
        // must not queue its transcript twice.
        var seen: Set<ConversationID> = []
        let work = conversations.compactMap { conversation -> BackfillTask? in
            guard seen.insert(conversation.id).inserted else { return nil }
            return backfill(for: conversation).map { BackfillTask(conversationID: conversation.id, kind: $0) }
        }
        guard !work.isEmpty else { return }
        logger.info("Backfilling chat history", metadata: [
            "conversations": "\(work.count)",
            "delta": "\(work.filter { $0.kind == .delta }.count)",
        ])

        await withTaskGroup(of: Void.self) { group in
            var next = 0
            // Start a window of tasks, then replace each as it finishes, so the queue drains at a
            // steady width instead of in lock-stepped batches.
            while next < min(Self.backfillConcurrency, work.count) {
                group.addTask { [task = work[next]] in await self.perform(task) }
                next += 1
            }
            while await group.next() != nil, next < work.count {
                group.addTask { [task = work[next]] in await self.perform(task) }
                next += 1
            }
        }
    }

    private func perform(_ task: BackfillTask) async {
        switch task.kind {
        case .delta:      await catchUp(conversationID: task.conversationID)
        case .newestPage: await loadMessages(for: task.conversationID)
        }
    }

    /// The work one conversation needs, or `nil` when its transcript is already current — or is
    /// already being fetched by the open chat, whose own load lands the same page.
    private func backfill(for conversation: Conversation) -> Backfill? {
        let conversationID = conversation.id
        guard !messageLoadsInFlight.contains(conversationID) else { return nil }

        // The cursor, not the presence of messages, is what says whether a transcript was ever pulled:
        // the feed persists each conversation's last-message preview as a message row before this runs,
        // so "holds a message" is true for nearly every chat in a feed the client has otherwise never
        // fetched. Only a newest page or an applied delta seats a cursor.
        let cursor = store.appliedCursor(for: conversationID)
        guard cursor > 0 else { return .newestPage }
        // A zero head means the server reported no sequence for this chat — nothing to compare against.
        return conversation.latestEventSequence > cursor ? .delta : nil
    }

    // MARK: - Persistence

    /// Mirrors a stream event into the local cache. Reads from the store's
    /// post-`apply` state so monotonic rules (read pointers) hold.
    private func persist(event: ConversationStreamEvent) {
        switch event {
        case .chatEvents(let conversationID, let events):
            // Read before the write: the newest stored id is the analytics watermark,
            // and after the upsert it would already include this batch.
            let countedThrough = (try? database.newestMessageID(conversationID: conversationID)) ?? nil
            let (reconciled, pairs) = reconciledForPersist(events.flatMap { $0.mutations.map(\.message) }, in: conversationID)
            // Messages + the advanced cursor persist atomically. `store.apply` already advanced the
            // in-memory cursor optimistically, so if this write rolls back, re-seat the cursor to the
            // persisted value and catch up — otherwise the un-persisted messages are skipped by the next
            // GetDelta and lost (the store no longer holds a confirmed copy).
            let ok = persist(operation: "apply-chat-events") {
                try database.persistMessages(reconciled, cursor: store.appliedCursor(for: conversationID), conversationID: conversationID)
            }
            if ok {
                commitReconciled(pairs, in: conversationID)
                receipts.countReceived(reconciled, countedThrough: countedThrough, delivery: .live)
            } else {
                store.reseatCursor((try? database.catchupCursor(conversationID: conversationID)) ?? 0, for: conversationID)
                scheduleGapCatchUp(conversationID)
            }
            refreshFeedPreview(for: conversationID)
            persistConversation(conversationID)
        case .metadataRefresh(let conversation):
            persistConversation(conversation)
            // A conversation entering the feed (e.g. re-hydrated after a stale feed snapshot dropped it)
            // regains its preview from the retained rows.
            refreshFeedPreview(for: conversation.id)
        case .lastActivityChanged(let conversationID, _),
             .readPointersChanged(let conversationID, _):
            persistConversation(conversationID)
        case .rosterChanged(let conversationID, _):
            // Persists whatever the store now holds: the roster patch it already folded into the
            // chat's member list and summary. A self-join's own snapshot arrives after this, from
            // `applyRosterMembership`, which persists it itself.
            persistConversation(conversationID)
            refreshFeedPreview(for: conversationID)
        case .viewerStateChanged(let conversationID, _):
            // Mute is cached so a chat restored cold renders muted rather than flickering unmuted
            // until the next metadata fetch — the same reason the roster summary is cached.
            persistConversation(conversationID)
        case .titleChanged(let conversationID, _),
             .pictureChanged(let conversationID, _):
            // Cached like the roster summary/mute above, so a cold restore shows the edited
            // title/picture rather than the stale one until the next full metadata fetch.
            persistConversation(conversationID)
        case .typingChanged:
            break
        case .reactionsChanged:
            // Written by `reactions`, which also holds the taps the update has to merge with.
            break
        }
    }

    /// Adopt pending sends' client ids onto *fresh* server echoes (ones not already persisted), so the
    /// persisted confirmed rows keep each send's identity and the echo collapses onto the pending row
    /// instead of duplicating it. A re-delivery of an already-stored id is left alone (it can't steal a
    /// send). Returns the enriched messages plus the matched pairs; the caller drops the matched
    /// pendings — via ``commitReconciled(_:in:)`` — only after the write persisting the batch succeeds,
    /// so a failed write never loses a send from the transcript.
    private func reconciledForPersist(_ messages: [ConversationMessage], in conversationID: ConversationID) -> (messages: [ConversationMessage], reconciled: [(clientID: UUID, confirmedID: MessageID)]) {
        // No pending send to reconcile against → skip the per-message existence probes (the common
        // receive/catch-up path, where every server message would otherwise cost a DB read).
        guard store.hasPendingMessages(for: conversationID) else { return (messages, []) }
        var claimed: Set<UUID> = []
        var pairs: [(clientID: UUID, confirmedID: MessageID)] = []
        let enriched = messages.map { message in
            guard message.clientMessageID == nil,
                  !((try? database.messageExists(id: message.id, conversationID: conversationID)) ?? true),
                  let clientID = store.pendingMatch(for: message, in: conversationID, excluding: claimed)
            else { return message }
            claimed.insert(clientID)
            pairs.append((clientID, message.id))
            var reconciled = message
            reconciled.clientMessageID = clientID
            return reconciled
        }
        return (enriched, pairs)
    }

    /// Drop the pending rows whose echoes just persisted, re-anchoring later still-pending sends.
    private func commitReconciled(_ pairs: [(clientID: UUID, confirmedID: MessageID)], in conversationID: ConversationID) {
        for pair in pairs {
            store.dropPending(clientMessageID: pair.clientID, confirmedAt: pair.confirmedID, in: conversationID)
        }
    }

    /// A freshly fetched newest page that does not overlap the retained history proves nothing about
    /// contiguity — the interior gap would render seamlessly stitched and can never be fetched (older
    /// paging anchors below the *oldest* persisted row). Drop the stale older epoch; it re-pages from
    /// the server on scroll. Must run before the page itself is persisted.
    private func dropStaleEpochIfNeeded(before page: [ConversationMessage], in conversationID: ConversationID) throws {
        guard let oldestOfPage = page.map(\.id.value).min(),
              let newestPersisted = try database.newestMessageID(conversationID: conversationID),
              newestPersisted.value < oldestOfPage else { return }
        try database.deleteMessages(conversationID: conversationID)
    }

    /// Recompute the feed row's preview from the newest persisted *visible* message (the store no longer
    /// holds the confirmed transcript to derive it from).
    func refreshFeedPreview(for conversationID: ConversationID) {
        let visible = (try? database.latestMessage(conversationID: conversationID)) ?? nil
        // A newest row that is itself invisible (a tombstone) is the one case the preview must regress —
        // the never-regress guard would otherwise keep showing the deleted content.
        let newestID = (try? database.newestMessageID(conversationID: conversationID)) ?? nil
        let newestIsTombstone: Bool = {
            guard let newestID, let visible else { return false }
            return newestID.value > visible.id.value
        }()
        store.setFeedPreview(visible, in: conversationID, force: newestIsTombstone)
    }

    /// Persists the store's current version of a conversation. No-ops for
    /// conversations the store doesn't know yet.
    func persistConversation(_ conversationID: ConversationID) {
        guard let conversation = store.conversations.first(where: { $0.id == conversationID }) else { return }
        persistConversation(conversation)
    }

    private func persistConversation(_ conversation: Conversation) {
        persist(operation: "upsert-conversation") { try database.upsertConversation(conversation) }
    }

    @discardableResult
    func persist(operation: String, _ write: () throws -> Void) -> Bool {
        do {
            try write()
            // A successful confirmed-message write invalidates the DB-backed transcript window; bump the
            // revision the coordinator observes so it re-reads.
            if Self.messageWriteOperations.contains(operation) {
                messageRevision &+= 1
            }
            return true
        } catch {
            logger.error("Failed to persist conversation state", metadata: [
                "operation": "\(operation)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to persist conversation state [\(operation)]")
            return false
        }
    }

    /// Persist operations that write confirmed messages — the ones that must bump `messageRevision`.
    private static let messageWriteOperations: Set<String> = [
        "upsert-messages", "apply-chat-events", "delta-batch", "load-messages", "load-older",
        "send-message", "reset-resync", "edit-message", "delete-message",
    ]

    // MARK: - Names

    /// Counterpart name shown when neither the synced contacts, the feed, nor a
    /// shared phone number provides one.
    static let fallbackCounterpartName = "Flipcash User"

    /// The counterpart's name for a conversation: the synced contact's
    /// address-book name, else the server-provided member name from the feed,
    /// else the counterpart's shared phone number, else a generic fallback.
    /// Tip DMs skip the contact lookup — their derived ids can never match a
    /// contact's, so the directory scan is a guaranteed miss.
    func displayName(for conversation: Conversation) -> String {
        // Group chats are named by their server-set title, not a counterpart.
        if let title = conversation.title, !title.isEmpty {
            return title
        }
        if conversation.type != .tipDm, let contactName = contactName(for: conversation.id) {
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

    /// The feed row's last-message line: the typing indicator while the
    /// counterpart types, the message text, or the cash summary, attributed to
    /// whoever wrote it. `currencyName` resolves a mint to its display name; nil —
    /// or the reserve, whose formatted amount already names itself — drops the
    /// "of …" suffix.
    func lastMessagePreview(for conversation: Conversation, currencyName: (PublicKey) -> String?) -> String? {
        if isCounterpartTyping(in: conversation.id) {
            return "Typing…"
        }
        guard let message = conversation.lastMessage else { return nil }
        let isFromSelf = message.isFromSelf(selfUserID)
        let senderName = groupSenderName(for: message, in: conversation, isFromSelf: isFromSelf)

        switch message.content {
        case .text(let text):
            // A bare prefix says less than no line at all, so an empty body previews as nothing.
            guard !text.isEmpty else { return nil }
            if isFromSelf { return "You: \(text)" }
            guard let senderName else { return text }
            return "\(senderName): \(text)"

        case .cash(let amount):
            let formatted = amount.nativeAmount.formatted()
            // The reserve would read "$1.00 of Dollars" — the amount alone already says it.
            let label: String
            if amount.mint != .usdf, let name = currencyName(amount.mint) {
                label = "\(formatted) of \(name)"
            } else {
                label = formatted
            }
            let isTip = message.cashAction == .tipped
            if let senderName {
                return isTip ? "\(senderName) tipped \(label)" : "\(senderName) sent \(label)"
            }
            if isFromSelf {
                return isTip ? "You tipped \(label)" : "You sent \(label)"
            }
            // "You received" holds only where the cash came to the viewer. In a group it went to
            // the chat and the viewer may have got none of it, so the amount stands on its own.
            return conversation.type == .group ? label : "You received \(label)"

        case .deleted:
            return nil
        }
    }

    /// The name a group row attributes its last message to, or `nil` when it should carry no
    /// attribution: the viewer's own message is covered by "You", a DM's other party is what the
    /// row is already titled after, and a sender the feed's roster subset omits has no name to
    /// print — this list fetches no profiles, so leaving the body unattributed is the honest
    /// fallback.
    private func groupSenderName(
        for message: ConversationMessage,
        in conversation: Conversation,
        isFromSelf: Bool
    ) -> String? {
        guard conversation.type == .group, !isFromSelf, let senderID = message.senderID else {
            return nil
        }
        let name = conversation.members.first { $0.userID == senderID }?.displayName
        return (name?.isEmpty ?? true) ? nil : name
    }

    func displayName(forConversationID conversationID: ConversationID) -> String {
        if let conversation = store.conversations.first(where: { $0.id == conversationID }) {
            return displayName(for: conversation)
        }
        return contactName(for: conversationID) ?? Self.fallbackCounterpartName
    }

    /// Seed values for the profile screen while the live profile loads: the
    /// counterpart's current name, handle, and avatar blurhash from the open
    /// conversation.
    func counterpartSeed(forUserID userID: UserID) -> CounterpartSeed {
        let member = conversations.flatMap(\.members).first { $0.userID == userID }
        return CounterpartSeed(
            name: member.flatMap { $0.displayName.isEmpty ? nil : $0.displayName },
            username: member?.username,
            imageData: nil,
            blurhash: member?.profilePicture?.thumbnailBlurhash
        )
    }

    /// The tip DM with `userID`, or nil when the viewer has none — what the counterpart's profile
    /// asks so it knows whether there is a chat to mute.
    ///
    /// Matched against the roster rather than through `counterpart(excluding:)`, which falls back to
    /// the first member and would answer a malformed single-member chat with the viewer themselves.
    /// Hidden chats are excluded: a blocked counterpart's DM is off the feed, and muting a chat the
    /// user can't see is not a control worth offering.
    func tipDM(withUserID userID: UserID) -> Conversation? {
        guard userID != selfUserID else { return nil }
        return conversations.first { conversation in
            conversation.type == .tipDm
                && !conversation.isHidden
                && conversation.members.contains { $0.userID == userID }
        }
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
        windowedMessages(for: conversationID, limit: Self.recentWindow)
    }

    /// Bumped after every successful confirmed-message DB write, so the coordinator — which reads the
    /// transcript from the DB, not the store — knows to re-read its window. Pending-overlay changes
    /// re-fire through the store directly.
    private(set) var messageRevision = 0

    /// Forces the transcript to re-read its window. `persist(operation:)` does this for database
    /// writes; an overlay change writes nothing, so it has to say so explicitly.
    func bumpMessageRevision() {
        messageRevision &+= 1
    }

    /// Set when a mutation needs to be reported to the person who made it. The screen presents it
    /// and clears it. `nil` means there is nothing to report.
    var mutationAlert: MutationAlert?

    /// A mutation the user has to be told about, because the transcript alone will not explain it.
    struct MutationAlert: Equatable, Identifiable {
        enum Kind: String, Equatable {
            /// Another client's change won; the transcript now shows that change, not this one.
            case conflict
            /// The request never applied; the transcript has reverted.
            case failure
        }

        let action: MessageCapability
        let kind: Kind

        var id: String { "\(action.rawValue)-\(kind.rawValue)" }

        var title: String {
            switch kind {
            case .conflict: "Message Changed"
            case .failure:
                switch action {
                case .edit:   "Couldn't Edit Message"
                case .delete: "Couldn't Delete Message"
                // Neither of these mutates the transcript, so neither can raise a mutation alert.
                // Report files straight from its sheet and reports its own outcome there.
                case .copy, .reply, .report: "Something Went Wrong"
                }
            }
        }

        var subtitle: String {
            switch kind {
            case .conflict:
                "This message changed somewhere else, so your change wasn't applied. The chat now shows the latest version."
            case .failure:
                "Check your connection and try again."
            }
        }
    }

    /// The transcript's bounded window with the in-memory optimistic overlay applied: every confirmed
    /// message from `startID` to the newest when anchored, else the newest `limit`. The DB is the source
    /// of the confirmed rows; the store contributes only the pending overlay. Anchoring by id means an
    /// arriving message grows the window at the tail instead of sliding the oldest revealed row out.
    func windowedMessages(for conversationID: ConversationID, startingAt startID: UInt64?, limit: Int) -> [ConversationMessage] {
        _ = messageRevision   // observe: re-read when a confirmed DB write lands
        let displayed = store.displayedMessages(for: conversationID, over: confirmedWindow(for: conversationID, startingAt: startID, limit: limit))
        return reactions.displayed(displayed, in: conversationID)
    }

    /// The confirmed rows behind ``windowedMessages(for:startingAt:limit:)``, cached against
    /// ``messageRevision``.
    ///
    /// The window read runs synchronously on the main actor on every observation tick, and an
    /// id-anchored window grows without bound as the reader pages back, so re-decoding it per tick
    /// is what a long group transcript feels as scroll jank. Nothing but a confirmed write can
    /// change these rows, and every such write bumps the revision — the pending overlay is applied
    /// on top by the caller and stays live.
    private func confirmedWindow(for conversationID: ConversationID, startingAt startID: UInt64?, limit: Int) -> [ConversationMessage] {
        let key = ConfirmedWindowKey(conversationID: conversationID, startID: startID, limit: limit, revision: messageRevision)
        if let cached = confirmedWindowCache, cached.key == key {
            return cached.messages
        }
        let confirmed: [ConversationMessage]
        if let startID {
            confirmed = (try? database.messages(conversationID: conversationID, from: startID)) ?? []
        } else {
            confirmed = (try? database.messagesWindow(conversationID: conversationID, before: nil, limit: limit)) ?? []
        }
        confirmedWindowCache = (key, confirmed)
        return confirmed
    }

    private struct ConfirmedWindowKey: Equatable {
        let conversationID: ConversationID
        let startID: UInt64?
        let limit: Int
        let revision: Int
    }

    /// One entry, not a table: a screen reads one chat's window, and the next open replaces it.
    @ObservationIgnored private var confirmedWindowCache: (key: ConfirmedWindowKey, messages: [ConversationMessage])?

    func windowedMessages(for conversationID: ConversationID, limit: Int) -> [ConversationMessage] {
        windowedMessages(for: conversationID, startingAt: nil, limit: limit)
    }

    /// The locally-stored copy of one message, regardless of whether it is inside the rendered
    /// window. Reply quotes read through this: a reply can point at a message far above the
    /// window, and resolving it must not page the server. Observes `messageRevision`, so a quote
    /// that resolves once history lands re-maps like any other change.
    func persistedMessage(_ messageID: MessageID, in conversationID: ConversationID) -> ConversationMessage? {
        _ = messageRevision   // observe: re-read when a confirmed DB write lands
        return (try? database.message(id: messageID, conversationID: conversationID)) ?? nil
    }

    /// Where the viewer's unread messages begin, from their stored READ pointer and the messages
    /// stored after it. Read once per visit, before ``advanceReadPointer(to:in:)`` moves the
    /// pointer — see ``UnreadBoundary``.
    func unreadBoundary(for conversationID: ConversationID) -> UnreadBoundary {
        UnreadBoundary.resolve(
            readPointer: store.selfReadPointer(for: conversationID, selfUserID: selfUserID),
            firstInbound: { readPointer in
                ((try? database.firstInboundMessageID(conversationID: conversationID, after: readPointer, excludingSender: selfUserID)) ?? nil)
                    .map(MessageID.init(value:))
            },
            unreadCount: { readPointer in
                (try? database.inboundMessageCount(conversationID: conversationID, after: readPointer, excludingSender: selfUserID)) ?? 0
            },
            hasStored: { readThrough in
                newestPersistedMessageID(through: readThrough, in: conversationID) != nil
            }
        )
    }

    /// The newest stored message id at or below `messageID`, or nil when none is stored.
    func newestPersistedMessageID(through messageID: MessageID, in conversationID: ConversationID) -> MessageID? {
        ((try? database.newestMessageID(conversationID: conversationID, through: messageID)) ?? nil).map(MessageID.init(value:))
    }

    /// The oldest confirmed id inside the newest-`limit` window — the anchor a first page-back grows
    /// from; nil when nothing is persisted.
    func oldestWindowedMessageID(for conversationID: ConversationID, limit: Int) -> UInt64? {
        ((try? database.messagesWindow(conversationID: conversationID, before: nil, limit: limit)) ?? []).first?.id.value
    }

    /// The persisted id `step` rows older than `before` — the loader's next window anchor — or nil when
    /// no older history is persisted locally (time to page the server).
    func olderAnchor(for conversationID: ConversationID, before: UInt64, step: Int) -> UInt64? {
        (try? database.olderAnchor(conversationID: conversationID, before: before, step: step)) ?? nil
    }

    /// The general "recent messages" window for the misc accessor.
    private static let recentWindow = 100

    /// The newest confirmed message, tombstones included — what the receive buzz and mark-read track, so
    /// an unresolved optimistic send never masks an incoming one, and a delete of the newest message
    /// doesn't regress the anchor to the previous row (which would buzz as if it just arrived).
    func lastConfirmedMessage(for conversationID: ConversationID) -> ConversationMessage? {
        _ = messageRevision   // observe: identity-keyed triggers must re-evaluate when a write lands
        return (try? database.newestMessage(conversationID: conversationID)) ?? nil
    }

    /// Whether the conversation holds any message — an in-flight optimistic send, or a persisted one.
    func hasMessages(for conversationID: ConversationID) -> Bool {
        _ = messageRevision
        return store.hasPendingMessages(for: conversationID) || (try? database.newestMessageID(conversationID: conversationID)).flatMap { $0 } != nil
    }

    func loadMessages(for conversationID: ConversationID) async {
        guard canRead(conversationID) else {
            logger.info("Skipping message load for a conversation the user may not read", metadata: [
                "conversationID": "\(conversationID)",
            ])
            return
        }
        messageLoadsInFlight.insert(conversationID)
        defer { messageLoadsInFlight.remove(conversationID) }
        do {
            let messages = try await messaging.getMessages(owner: owner, conversationID: conversationID, before: nil)
            logger.info("Loaded conversation messages", metadata: [
                "conversationID": "\(conversationID)",
                "count": "\(messages.count)",
            ])
            // Establish the event-log frontier from the newest page so a following catch-up resumes from
            // head — fetching only genuinely newer messages, appended at the tail — instead of a
            // `GetDelta(after: 0)` that re-pulls the whole history and prepends it, knocking the
            // transcript off the bottom on first open. Page + cursor land atomically (a failed write
            // must not seat the cursor past messages that never persisted), and a non-overlapping page
            // drops the stale older epoch first.
            let (reconciled, pairs) = reconciledForPersist(messages, in: conversationID)
            let head = messages.map(\.eventSequence).max() ?? 0
            let ok = persist(operation: "load-messages") {
                try dropStaleEpochIfNeeded(before: messages, in: conversationID)
                try database.persistMessages(reconciled, cursor: head, conversationID: conversationID)
            }
            if ok {
                commitReconciled(pairs, in: conversationID)
                if head > 0 { store.setAppliedCursor(head, for: conversationID) }
            }
            refreshFeedPreview(for: conversationID)
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

    /// Pages strictly older than the oldest loaded message, prepends it to the in-memory window, and
    /// persists it — retention is on, so paged-in history stays in the DB and a reopen reads it locally
    /// instead of re-fetching. No-ops while a page is in flight or once history is exhausted.
    func loadOlderMessages(for conversationID: ConversationID) async {
        guard canRead(conversationID) else { return }
        guard hasMoreOlderMessages(for: conversationID), !isLoadingOlderMessages(for: conversationID) else { return }
        // Page before the oldest PERSISTED id — the DB holds all viewed history; the store may be trimmed.
        guard let oldest = (try? database.oldestMessageID(conversationID: conversationID)).flatMap({ $0 }) else { return }

        olderPageState[conversationID, default: OlderPageState()].isLoading = true
        defer { olderPageState[conversationID]?.isLoading = false }

        do {
            let older = try await messaging.getMessages(owner: owner, conversationID: conversationID, before: oldest)
            if older.isEmpty {
                olderPageState[conversationID]?.hasMore = false
            } else {
                // Retention is on, so persist the paged-in history: the next open reads it from the DB
                // instead of re-fetching. Prepended history must not play insertion transitions — the
                // revision bump and the resulting re-read ride an animation-suppressed transaction.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    _ = persist(operation: "load-older") { try database.upsertConversationMessages(older, conversationID: conversationID) }
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
    func send(
        _ text: String,
        to conversationID: ConversationID,
        repliedTo: MessageID? = nil,
        restoringOnFailure draft: ChatDraft? = nil
    ) async -> Bool {
        let clientMessageID = UUID()
        let pending = ConversationMessage(
            id: .unassigned,
            senderID: selfUserID,
            content: .text(text),
            date: .now,
            unreadSeq: 0,
            repliedTo: repliedTo,
            status: .sending,
            clientMessageID: clientMessageID
        )
        let anchor = (try? database.newestMessageID(conversationID: conversationID)).flatMap { $0 }?.value ?? 0
        store.insertPending(pending, anchoredTo: anchor, into: conversationID)
        receiptSettle.hold(clientMessageID.uuidString)
        // The composer's own snapshot, carried down rather than re-derived: only the bar holds the
        // untrimmed text and the reply strip's author and snippet, and it has already cleared both
        // by the time a failure comes back.
        if let draft {
            failedSends?.willSend(draft, clientMessageID: clientMessageID, in: conversationID)
        }
        return await deliver(clientMessageID: clientMessageID, text: text, repliedTo: repliedTo, to: conversationID)
    }

    /// Re-send a failed optimistic message, reusing its client id so the server (idempotent on it)
    /// returns the original message rather than creating a duplicate. Only a `.failed` row is retried,
    /// so a double-tap (or a tap during a slow in-flight retry) can't fire concurrent sends.
    func retry(clientMessageID: UUID, in conversationID: ConversationID) async {
        guard let pending = store.pendingMessage(clientMessageID: clientMessageID, in: conversationID),
              pending.status == .failed,
              case .text(let text) = pending.content else { return }
        store.markPending(clientMessageID: clientMessageID, status: .sending, in: conversationID)
        _ = await deliver(clientMessageID: clientMessageID, text: text, repliedTo: pending.repliedTo, to: conversationID)
    }

    private func deliver(clientMessageID: UUID, text: String, repliedTo: MessageID?, to conversationID: ConversationID) async -> Bool {
        // Captured before the send so success and failure report the same
        // conversation kind; an unresolved conversation reports as Unknown.
        let chatType = conversation(withID: conversationID)?.type
        do {
            let message = try await messaging.sendMessage(
                owner: owner,
                conversationID: conversationID,
                text: text,
                repliedTo: repliedTo,
                clientMessageID: clientMessageID
            )
            // Persist the row carrying its client id (the server echoes none) so the DB keeps the send's
            // identity across a round-trip. The pending row is dropped only once the confirmed copy is
            // durably readable — a failed write leaves the send visible (the stream echo or a catch-up
            // reconciles it later) instead of vanishing it.
            var confirmed = message
            confirmed.clientMessageID = clientMessageID
            let ok = persist(operation: "send-message") { try database.upsertConversationMessages([confirmed], conversationID: conversationID) }
            if ok {
                store.dropPending(clientMessageID: clientMessageID, confirmedAt: message.id, in: conversationID)
            } else {
                scheduleGapCatchUp(conversationID)
            }
            store.advanceLastActivity(to: message.date, in: conversationID)
            refreshFeedPreview(for: conversationID)
            persistConversation(conversationID)
            // Outside the `ok` branch: the message reached the server either way, so a draft put
            // back by an earlier failure has been sent and must not be restored again.
            failedSends?.didSucceed(clientMessageID: clientMessageID)
            Analytics.sentMessage(chatType: chatType)
            return true
        } catch {
            store.markPending(clientMessageID: clientMessageID, status: .failed, in: conversationID)
            // `.failed` is memory-only here — the schema has no send-status column — so the words
            // go back to the draft store, which is the only thing that survives leaving the chat.
            failedSends?.didFail(clientMessageID: clientMessageID)
            logger.error("Failed to send conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to send conversation message")
            Analytics.sentMessage(chatType: chatType, error: error)
            return false
        }
    }

    /// Moves the viewer's READ pointer to `messageID`, the newest message someone else sent that has
    /// been on screen. Never moves it backward.
    ///
    /// The local pointer moves first, so the feed's unread state follows the screen at once, and the
    /// inbound messages it crossed report their receipts. `AdvancePointer` goes out after. When it
    /// fails, the local pointer stays ahead and the next feed load sends it again. Android's
    /// `MessagingDelegate.advanceReadPointer` works in the same order.
    func advanceReadPointer(to messageID: MessageID, in conversationID: ConversationID) {
        // A pointer advance is denied to a non-member even when the fetch isn't, and a chat the user
        // cannot read has nothing to mark.
        guard canAdvancePointer(conversationID) else { return }
        // A chat not in the feed yet has no member row to hold the pointer, only the unsynced entry.
        let previous = [
            store.selfReadPointer(for: conversationID, selfUserID: selfUserID),
            store.unsyncedSelfReadPointers[conversationID],
        ].compactMap { $0 }.max()
        if let previous, messageID <= previous { return }
        store.advanceSelfReadPointer(to: messageID, in: conversationID, selfUserID: selfUserID)
        // The pointer only moves forward, so the window it just crossed holds exactly the messages the
        // reader is seeing for the first time. The reporter keeps only the inbound ones.
        let crossed = (try? database.messages(conversationID: conversationID, after: previous, through: messageID)) ?? []
        receipts.reportRead(crossed, chatType: conversation(withID: conversationID)?.type)
        persistConversation(conversationID)
        syncReadPointer(in: conversationID)
    }

    /// Sends the viewer's unsynced READ pointer for `conversationID`, if it has one. Called as the
    /// chat closes, so an advance whose send failed gets another try then.
    func flushReadPointer(in conversationID: ConversationID) {
        syncReadPointer(in: conversationID)
    }

    /// Sends `AdvancePointer` for the local pointer until the server holds it, one call in flight per
    /// chat. A call that lands while an older one is in flight is carried by the loop, so a burst of
    /// advances sends the newest id rather than every step.
    private func syncReadPointer(in conversationID: ConversationID) {
        guard readPointerSyncTasks[conversationID] == nil,
              store.unsyncedSelfReadPointers[conversationID] != nil else { return }
        readPointerSyncTasks[conversationID] = Task { [weak self] in
            await self?.sendUnsyncedReadPointer(in: conversationID)
            self?.readPointerSyncTasks[conversationID] = nil
        }
    }

    private func sendUnsyncedReadPointer(in conversationID: ConversationID) async {
        while !Task.isCancelled, let target = store.unsyncedSelfReadPointers[conversationID] {
            do {
                try await messaging.markRead(owner: owner, conversationID: conversationID, messageID: target)
                store.didSyncSelfReadPointer(target, in: conversationID)
            } catch {
                logger.error("Failed to advance read pointer", metadata: [
                    "conversationID": "\(conversationID)",
                    "error": "\(error)",
                ])
                ErrorReporting.captureError(error, reason: "Failed to advance read pointer")
                return
            }
        }
    }

    /// Re-sends every READ pointer the server is behind on, after a feed load has shown which those
    /// are, and writes the kept local pointer back over the server copy the load just persisted.
    /// Receipts are not reported again; they went out with the local advance. Android's
    /// `MessagingDelegate.reportReadPointer` does the same.
    private func resendUnsyncedReadPointers() {
        for conversationID in store.unsyncedSelfReadPointers.keys where canAdvancePointer(conversationID) {
            persistConversation(conversationID)
            syncReadPointer(in: conversationID)
        }
    }

    // MARK: - Outgoing typing

    /// Broadcasts the user's typing state as the draft text changes.
    func draftDidChange(_ text: String, in conversationID: ConversationID) {
        typing.draftDidChange(text, in: conversationID)
    }

    /// Stops broadcasting the user's typing state in the conversation.
    func stopSelfTyping(in conversationID: ConversationID) {
        typing.stopSelfTyping(in: conversationID)
    }
}

/// Seed data for the profile screen before the live profile fetch returns.
struct CounterpartSeed: Sendable {

    /// The counterpart's own name, or `nil` for an account that hasn't set
    /// one — the profile screen titles those by handle instead.
    let name: String?

    let username: Username?
    let imageData: Data?
    let blurhash: String?
}
