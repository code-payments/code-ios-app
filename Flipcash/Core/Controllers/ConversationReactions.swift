//
//  ConversationReactions.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.conversation-reactions")

/// Emoji reactions on chat messages: the user's taps, the add/remove calls they turn into, and the
/// reaction updates the stream delivers.
///
/// Confirmed reaction state lives on the stored message row. This unit holds a message's state in
/// memory only while a tap is pending or a call is on the wire, and overlays it on the transcript so a
/// tap shows before the server answers.
@MainActor
@Observable
final class ConversationReactions {

    struct Key: Hashable {
        let conversationID: ConversationID
        let messageID: MessageID
    }

    /// The messages with a tap pending or a call on the wire; a settled state lives only on its row.
    private var held: [Key: ReactionState] = [:]

    /// The newest reaction failure the user has to be told about. The screen shows it and clears it.
    var error: ReactionError?

    /// Counts the user's reaction adds for the strip's recents. Wired by the session before use.
    @ObservationIgnored var recents: RecentReactionsStore?

    /// Called after every write to a stored message's reactions, so the transcript re-reads its rows.
    @ObservationIgnored var didPersist: () -> Void = {}

    @ObservationIgnored private let messaging: any ConversationMessaging
    @ObservationIgnored private let database: Database
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let selfUserID: UserID

    init(messaging: any ConversationMessaging, database: Database, owner: KeyPair, selfUserID: UserID) {
        self.messaging = messaging
        self.database = database
        self.owner = owner
        self.selfUserID = selfUserID
    }

    /// Turns the user's reaction with `emoji` on the message on or off, whichever it is not showing.
    func toggle(_ emoji: String, messageID: MessageID, in conversationID: ConversationID, at date: Date = .now) {
        let key = Key(conversationID: conversationID, messageID: messageID)
        var state = current(key)
        let wasReacted = state.selfReactions.contains { $0.emoji == emoji }
        let call = state.tap(emoji, at: date)
        if !wasReacted {
            recents?.record(emoji, at: date)
        }
        hold(state, for: key)
        if let call {
            send(call, for: key)
        }
    }

    /// Applies reaction updates the stream delivered for one conversation.
    func apply(_ updates: [DecodedReactionUpdate], in conversationID: ConversationID) {
        let byMessage = Dictionary(grouping: updates, by: \.messageID)
        for (messageID, updates) in byMessage {
            let key = Key(conversationID: conversationID, messageID: messageID)
            let applyAll: (inout ReactionState) -> Void = { [selfUserID] state in
                for update in updates {
                    state.applyUpdate(
                        emoji: update.emoji,
                        actorIsSelf: update.actor == selfUserID,
                        added: update.added,
                        count: update.count,
                        version: update.version,
                        reactedAt: update.reactedAt
                    )
                }
            }
            if var state = held[key] {
                applyAll(&state)
                held[key] = state
            }
            write(for: key, operation: "apply-reaction-updates", applyAll)
        }
    }

    /// Brings the stored reactions of `messageIDs` up to the server's current summaries. Reactions
    /// change without a message's event sequence moving, so a cached copy never learns of the ones
    /// made while this account wasn't listening; the contract has clients refresh them on view.
    func refresh(_ messageIDs: [MessageID], in conversationID: ConversationID) async {
        guard !messageIDs.isEmpty else { return }
        let summaries: [MessageID: ReactionState]
        do {
            summaries = try await messaging.getReactionSummaries(owner: owner, conversationID: conversationID, messageIDs: messageIDs)
        } catch {
            logger.error("Failed to refresh message reactions", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to refresh message reactions")
            return
        }
        logger.info("Refreshed message reactions", metadata: [
            "conversationID": "\(conversationID)",
            "requested": "\(messageIDs.count)",
            "returned": "\(summaries.count)",
        ])
        for (messageID, summary) in summaries {
            let key = Key(conversationID: conversationID, messageID: messageID)
            if var state = held[key] {
                state.applySummary(summary.summaryEntries)
                held[key] = state
            }
        }
        do {
            if try database.mergeReactions(summaries, conversationID: conversationID) > 0 {
                didPersist()
            }
        } catch {
            logger.error("Failed to persist message reactions", metadata: [
                "operation": "refresh-reactions",
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to persist message reactions [refresh-reactions]")
        }
    }

    /// `messages` with each held state overlaid on its stored one.
    func displayed(_ messages: [ConversationMessage], in conversationID: ConversationID) -> [ConversationMessage] {
        guard !held.isEmpty else { return messages }
        return messages.map { message in
            guard var state = held[Key(conversationID: conversationID, messageID: message.id)] else {
                return message
            }
            if let stored = message.reactionState {
                state.merge(stored)
            }
            var displayed = message
            displayed.reactionState = state
            return displayed
        }
    }

    /// The failure a thrown reaction call settles with; anything that is not the server's answer
    /// counts as the network.
    nonisolated static func failure(for error: any Error) -> ReactionFailure {
        switch error {
        case let error as ErrorAddReaction: error.reactionFailure
        case let error as ErrorRemoveReaction: error.reactionFailure
        default: .network
        }
    }

    // MARK: - Private

    /// The held state brought up to date with the stored one, or the stored one alone.
    private func current(_ key: Key) -> ReactionState {
        let stored: ReactionState?
        do {
            stored = try database.message(id: key.messageID, conversationID: key.conversationID)?.reactionState
        } catch {
            logger.error("Failed to read message reactions", metadata: [
                "conversationID": "\(key.conversationID)",
                "messageID": "\(key.messageID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to read message reactions")
            stored = nil
        }
        guard var state = held[key] else { return stored ?? ReactionState() }
        if let stored {
            state.merge(stored)
        }
        return state
    }

    private func hold(_ state: ReactionState, for key: Key) {
        held[key] = state.isSettled ? nil : state
    }

    private func send(_ call: ReactionCall, for key: Key) {
        Task { [weak self, messaging, owner] in
            let result: ReactionResult
            do {
                let reaction = switch call.op {
                case .add:
                    try await messaging.addReaction(owner: owner, conversationID: key.conversationID, messageID: key.messageID, emoji: call.emoji)
                case .remove:
                    try await messaging.removeReaction(owner: owner, conversationID: key.conversationID, messageID: key.messageID, emoji: call.emoji)
                }
                result = reaction.result
            } catch {
                logger.error("Failed to change message reaction", metadata: [
                    "conversationID": "\(key.conversationID)",
                    "messageID": "\(key.messageID)",
                    "error": "\(error)",
                ])
                ErrorReporting.captureError(error, reason: "Failed to change message reaction")
                result = .failed(Self.failure(for: error))
            }
            self?.complete(call, with: result, for: key)
        }
    }

    private func complete(_ call: ReactionCall, with result: ReactionResult, for key: Key) {
        var state = current(key)
        let (next, error) = state.respond(emoji: call.emoji, result: result)
        if let error {
            self.error = error
        }
        if case .ok = result {
            let confirmed = state
            write(for: key, operation: "confirm-reaction") { $0.merge(confirmed) }
        }
        hold(state, for: key)
        if let next {
            send(next, for: key)
        }
    }

    private func write(for key: Key, operation: String, _ transform: (inout ReactionState) -> Void) {
        do {
            try database.updateReactions(messageID: key.messageID, conversationID: key.conversationID, transform)
            didPersist()
        } catch {
            logger.error("Failed to persist message reactions", metadata: [
                "operation": "\(operation)",
                "conversationID": "\(key.conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to persist message reactions [\(operation)]")
        }
    }
}
