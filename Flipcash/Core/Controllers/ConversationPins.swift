//
//  ConversationPins.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The pinned messages of the chats the user opens: the list fetched on open, the `PinsChanged`
/// updates that keep it current, and the user's pins and unpins.
///
/// Held in memory only. A chat feed carries no pin summary, so a chat whose list was never fetched
/// has no pins here rather than "no pins".
@MainActor
@Observable
final class ConversationPins {

    /// What a pin attempt came to.
    enum PinOutcome: Equatable {
        case pinned
        /// The chat is at the server's pin cap; the viewer has to unpin one first.
        case full
        case failed
    }

    /// A message the viewer tried to pin at the cap, pinned once an unpin frees a slot.
    struct PendingPin: Hashable {
        let conversationID: ConversationID
        let messageID: MessageID
    }

    /// Each fetched chat's pins.
    private var lists: [ConversationID: PinnedMessages] = [:]

    /// The pin each chat's bar shows, by message; the newest visible pin when unset.
    private var barCursors: [ConversationID: MessageID] = [:]

    /// The message waiting on a free slot, set by a pin at the cap.
    private(set) var pendingPin: PendingPin?

    /// Chats with a fetch on the wire, so overlapping triggers share one.
    @ObservationIgnored private var fetching: Set<ConversationID> = []

    /// Called after every change to a chat's pinned ids, so the transcript re-reads its menus.
    @ObservationIgnored var didChange: () -> Void = {}

    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let selfUserID: UserID

    init(messaging: any ConversationMessaging, owner: KeyPair, selfUserID: UserID) {
        self.messaging = messaging
        self.owner = owner
        self.selfUserID = selfUserID
    }

    // MARK: - Reads

    /// The chat's pins, or nil before its list is fetched.
    func list(in conversationID: ConversationID) -> PinnedMessages? {
        lists[conversationID]
    }

    /// The pins a viewer sees, most recently pinned first.
    func visible(in conversationID: ConversationID) -> [ConversationPin] {
        lists[conversationID]?.visible ?? []
    }

    /// The ids of every pinned message in the chat, deleted ones included.
    func pinnedIDs(in conversationID: ConversationID) -> Set<MessageID> {
        lists[conversationID]?.messageIDs ?? []
    }

    /// The pin the chat's bar shows.
    func barPin(in conversationID: ConversationID) -> ConversationPin? {
        lists[conversationID]?.shown(barCursors[conversationID])
    }

    /// Moves the bar on to the next older pin, wrapping to the newest; called after a bar tap jumps.
    func advanceBar(in conversationID: ConversationID) {
        guard let list = lists[conversationID] else { return }
        let shown = list.shown(barCursors[conversationID])
        barCursors[conversationID] = list.pin(after: shown?.messageID)?.messageID
    }

    // MARK: - Fetch

    /// Fetches the chat's pins, replacing what was held. Pages through every pin the server holds.
    func load(_ conversationID: ConversationID) async {
        guard fetching.insert(conversationID).inserted else { return }
        defer { fetching.remove(conversationID) }
        do {
            var pins: [ConversationPin] = []
            var version: UInt64 = 0
            var token: Data?
            repeat {
                let page = try await messaging.getPinnedMessages(owner: owner, conversationID: conversationID, pagingToken: token)
                pins.append(contentsOf: page.pins)
                if let summary = page.summary { version = max(version, summary.version) }
                token = page.hasMore && !page.pagingToken.isEmpty ? page.pagingToken : nil
            } while token != nil
            store(PinnedMessages(pins: pins, version: version), in: conversationID)
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to fetch pinned messages")
        }
    }

    // MARK: - Stream

    /// Applies the stream's pin updates and the edits and deletes of pinned messages.
    func apply(_ event: ConversationStreamEvent) {
        switch event {
        case .pinsChanged(let conversationID, let change, let summary):
            apply(change, summary: summary, in: conversationID)
        case .metadataRefresh(let conversation):
            // A chat read carries the summary without the change; a newer one means a refetch.
            guard let summary = conversation.pinSummary else { return }
            apply(nil, summary: summary, in: conversation.id)
        case .chatEvents(let conversationID, let events):
            guard var list = lists[conversationID] else { return }
            var changed = false
            for mutation in events.flatMap(\.mutations) {
                switch mutation {
                case .edited(let message), .deleted(let message):
                    changed = list.replace(message) || changed
                case .sent:
                    continue
                }
            }
            if changed { store(list, in: conversationID) }
        case .lastActivityChanged, .readPointersChanged, .typingChanged, .rosterChanged, .viewerStateChanged,
             .titleChanged, .pictureChanged, .coverPictureChanged, .descriptionChanged, .reactionsChanged,
             .lobbyChanged, .rulesChanged, .paymentRequestsChanged:
            return
        }
    }

    private func apply(_ change: ConversationPinChange?, summary: ConversationPinSummary, in conversationID: ConversationID) {
        // A chat never opened has no list to keep current; opening it fetches one.
        guard var list = lists[conversationID] else { return }
        switch list.apply(change, summary: summary) {
        case .applied:
            store(list, in: conversationID)
        case .needsRefetch:
            Task { await load(conversationID) }
        case .stale:
            return
        }
    }

    // MARK: - Pin / unpin

    /// Pins `message`. At the cap, holds it as ``pendingPin`` and answers `.full`.
    func pin(_ message: ConversationMessage, in conversationID: ConversationID) async -> PinOutcome {
        do {
            let summary = try await messaging.pinMessage(owner: owner, conversationID: conversationID, messageID: message.id)
            let pin = summary.latest?.messageID == message.id
                ? summary.latest
                : ConversationPin(messageID: message.id, pinnedBy: selfUserID, pinnedAt: .now, message: message)
            applyOwn(pin.map { .pinned($0) }, summary: summary, in: conversationID)
            if pendingPin?.messageID == message.id { pendingPin = nil }
            return .pinned
        } catch ErrorPinMessage.tooManyPins {
            pendingPin = PendingPin(conversationID: conversationID, messageID: message.id)
            return .full
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to pin message")
            return .failed
        }
    }

    /// Unpins the message `messageID`. Returns whether the server took it.
    func unpin(_ messageID: MessageID, in conversationID: ConversationID) async -> Bool {
        do {
            let summary = try await messaging.unpinMessage(owner: owner, conversationID: conversationID, messageID: messageID)
            applyOwn(.unpinned(messageID), summary: summary, in: conversationID)
            return true
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to unpin message")
            return false
        }
    }

    /// Drops the message waiting on a free slot, when the viewer closes the list without unpinning.
    func cancelPendingPin() {
        pendingPin = nil
    }

    /// Applies the answer to the viewer's own pin or unpin. The stream's echo of the same version is
    /// then stale; a version that skipped ahead of the list refetches.
    private func applyOwn(_ change: ConversationPinChange?, summary: ConversationPinSummary, in conversationID: ConversationID) {
        guard lists[conversationID] != nil else {
            Task { await load(conversationID) }
            return
        }
        apply(change, summary: summary, in: conversationID)
    }

    private func store(_ list: PinnedMessages, in conversationID: ConversationID) {
        let held = Set(lists[conversationID]?.messageIDs ?? [])
        let idsChanged = held != Set(list.messageIDs)
        // A new pin takes the bar, the way a fresh chat opens on its newest pin.
        if !Set(list.messageIDs).isSubset(of: held) { barCursors[conversationID] = nil }
        lists[conversationID] = list
        if idsChanged { didChange() }
    }
}
