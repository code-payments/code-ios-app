//
//  ConversationStreamEvent.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A decoded update delivered over the single per-user event stream. The
/// streamer demultiplexes raw `ChatUpdate`s into these so the controller can
/// apply them without touching proto types.
public enum ConversationStreamEvent: Sendable {

    /// Durable, sequenced event-log mutations for a conversation (message sent/edited/deleted). The
    /// store applies them last-writer-wins by `event_sequence` and gap-detects via `sequence`/`count`,
    /// catching up with `GetDelta` on a gap.
    case chatEvents(conversationID: ConversationID, events: [DecodedChatEvent])

    /// A conversation's full metadata was refreshed (members/last message/last activity).
    case metadataRefresh(Conversation)

    /// Only a conversation's last-activity timestamp changed — re-sort the feed.
    case lastActivityChanged(conversationID: ConversationID, date: Date)

    /// One or more members' READ watermarks advanced.
    case readPointersChanged(conversationID: ConversationID, pointers: [MemberReadPointer])

    /// One or more members started or stopped typing. Ephemeral — never persisted or part of the
    /// event log; the controller holds it as transient UI state and the server clears it with a
    /// stopped/timed-out notification.
    case typingChanged(conversationID: ConversationID, notifications: [TypingNotification])

    /// One or more members joined or left the roster. Like `readPointersChanged`, this rides outside
    /// the gap-detected event log as a convergent overlay — the store applies each update by
    /// `RosterSummary.version` (a greater version wins, drop-if-not-greater), so delivery order
    /// doesn't matter.
    case rosterChanged(conversationID: ConversationID, updates: [DecodedRosterUpdate])

    /// The signed-in user's viewer state changed (currently: mute status, permissions). Compared
    /// like `rosterChanged` — apply by ``ConversationViewerState/version``, greater wins, drop the
    /// rest.
    case viewerStateChanged(conversationID: ConversationID, viewerState: ConversationViewerState)

    /// A group chat's title changed (via `Chat.EditChat`), including on the editor's other devices.
    /// Best-effort and applied as received, with no version to compare — a client that suspects a
    /// miss refetches the chat via `Chat.GetChat`.
    case titleChanged(conversationID: ConversationID, title: String)

    /// A group chat's description changed (via `Chat.EditChat`), including on the editor's other
    /// devices. An empty `description` means it was cleared. Best-effort and applied as received,
    /// like ``titleChanged``.
    case descriptionChanged(conversationID: ConversationID, description: String)

    /// A group chat's picture changed (via `Chat.EditChat`), including on the editor's other
    /// devices. Best-effort and applied as received, like ``titleChanged``.
    case pictureChanged(conversationID: ConversationID, picture: ProfilePicture)

    /// A group chat's cover picture changed (via `Chat.EditChat`), including on the editor's other
    /// devices. Best-effort and applied as received, like ``titleChanged``.
    case coverPictureChanged(conversationID: ConversationID, coverPicture: ProfilePicture)

    /// Reactions on messages in the chat changed. Best-effort and outside the gap-detected event
    /// log: each update is applied by its per-emoji version, and a missed one is reconciled by the
    /// next reaction summary.
    case reactionsChanged(conversationID: ConversationID, updates: [DecodedReactionUpdate])

    /// Members entered or left a private chat's lobby. Delivered to the chat's admitting members;
    /// surfaced as received, with no version to compare.
    case lobbyChanged(conversationID: ConversationID, updates: [LobbyUpdate])

    /// A group chat's rules changed (via `Chat.EditChat`), including on the editor's other devices.
    /// `rules` is the full replacement set. Best-effort and applied as received, like ``titleChanged``.
    case rulesChanged(conversationID: ConversationID, rules: ConversationRules)

    /// A message was pinned or unpinned. Like ``rosterChanged``, a convergent overlay: the store keeps
    /// `summary` only when its version is greater than the one held. `summary` is always set on the wire,
    /// so an update without it is dropped at decode.
    case pinsChanged(conversationID: ConversationID, change: ConversationPinChange?, summary: ConversationPinSummary)

    /// Payment requests in the chat changed. Best-effort and outside the gap-detected event log: a
    /// missed update is reconciled by the next fetch of the request. Applying them to request state
    /// follows `PaymentRequestUpdate`'s contract; see ``DecodedPaymentRequestUpdate``.
    case paymentRequestsChanged(conversationID: ConversationID, updates: [DecodedPaymentRequestUpdate])
}

/// One reaction added or removed on one message.
public struct DecodedReactionUpdate: Hashable, Sendable {
    public let messageID: MessageID
    public let emoji: String
    public let actor: UserID
    /// True for an add or a boost, false for a remove. A boost adds the actor's reaction when it is
    /// absent, so it applies to reaction state as an add.
    public let added: Bool
    /// True when the actor paid to boost the emoji. Such a reaction cannot be removed afterwards.
    public let boosted: Bool
    /// The emoji's total reactor count after the change.
    public let count: UInt64
    public let version: UInt64
    public let reactedAt: Date?
    /// The emoji's total boost after the change, in USD.
    public let boostUSD: Double
    /// The actor's own total boost on the emoji after the change, in USD; 0 unless `boosted`.
    public let actorBoostUSD: Double

    public init(messageID: MessageID, emoji: String, actor: UserID, added: Bool, boosted: Bool = false, count: UInt64, version: UInt64, reactedAt: Date?, boostUSD: Double = 0, actorBoostUSD: Double = 0) {
        self.messageID = messageID
        self.emoji = emoji
        self.actor = actor
        self.added = added
        self.boosted = boosted
        self.count = count
        self.version = version
        self.reactedAt = reactedAt
        self.boostUSD = boostUSD
        self.actorBoostUSD = actorBoostUSD
    }
}

extension DecodedReactionUpdate {
    /// Nil for an update whose action this client does not know or whose actor does not parse.
    init?(_ proto: Flipcash_Messaging_V1_ReactionUpdate) {
        let added: Bool
        let boosted: Bool
        switch proto.action {
        case .added: (added, boosted) = (true, false)
        case .removed: (added, boosted) = (false, false)
        case .boosted: (added, boosted) = (true, true)
        case .unknown, .UNRECOGNIZED: return nil
        }
        guard let actor = try? UUID(data: proto.actor.value) else { return nil }
        self.init(
            messageID: MessageID(proto.messageID),
            emoji: proto.emoji.value,
            actor: actor,
            added: added,
            boosted: boosted,
            count: proto.count,
            version: proto.version,
            reactedAt: proto.hasReactedTs ? proto.reactedTs.date : nil,
            boostUSD: proto.boostUsd,
            actorBoostUSD: proto.actorBoostUsd
        )
    }
}

/// One durable event in a chat's log: a contiguous run of mutations delivered atomically. `sequence`
/// is the END of the half-open range this event occupies; `count` is the number of mutations. Clients
/// apply mutations in ascending `sequence` and gap-detect via `localCursor + count == sequence`.
public struct DecodedChatEvent: Sendable {
    public let sequence: UInt64
    public let count: UInt64
    public let mutations: [DecodedMutation]

    public init(sequence: UInt64, count: UInt64, mutations: [DecodedMutation]) {
        self.sequence = sequence
        self.count = count
        self.mutations = mutations
    }
}

/// A single mutation within an event. Each carries the full materialized message; a delete carries a
/// `.deleted` tombstone. The store applies them uniformly by last-writer-wins.
public enum DecodedMutation: Sendable {
    case sent(ConversationMessage)
    case edited(ConversationMessage)
    case deleted(ConversationMessage)

    /// The materialized message this mutation applies (a send, the edited state, or the tombstone).
    public var message: ConversationMessage {
        switch self {
        case .sent(let message), .edited(let message), .deleted(let message):
            return message
        }
    }
}

/// A member's READ watermark from a live pointer update: everything at or before
/// `value` is read by `userID`. `date` is when they advanced the pointer, for
/// the read receipt; `nil` when the server omits the timestamp.
public struct MemberReadPointer: Sendable, Hashable {
    public let userID: UserID
    public let value: MessageID
    public let date: Date?

    public init(userID: UserID, value: MessageID, date: Date? = nil) {
        self.userID = userID
        self.value = value
        self.date = date
    }
}

/// One live roster change from a `RosterUpdate`: the chat's roster summary after the change (compared
/// by ``ConversationRosterSummary/version`` — apply a greater version, drop the rest) and what
/// changed. Delivered to every member of the chat, including — for a join — the joining member's
/// other devices and — for a leave — the leaving member themself.
public struct DecodedRosterUpdate: Sendable {
    public let rosterSummary: ConversationRosterSummary
    public let change: RosterChange

    public init(rosterSummary: ConversationRosterSummary, change: RosterChange) {
        self.rosterSummary = rosterSummary
        self.change = change
    }
}

/// What changed in a roster update.
public enum RosterChange: Sendable {
    /// A member joined. `chat` is the full chat snapshot, set only when the signed-in user is the
    /// member who joined — the recipient inserts it into their feed directly, without a refetch.
    /// `nil` for every other member's join.
    case joined(member: ConversationMember, chat: Conversation?)
    /// A member left. Naming the signed-in user means the recipient is no longer a member and should
    /// remove the chat from their feed.
    case left(userID: UserID)
    /// Membership changed in a way the update doesn't itemize (`RosterUpdate.MembershipChanged`).
    /// Only the summary applies: the cached member list stays as it is, and the update is not a
    /// version gap, so it never triggers a roster refetch.
    case membershipChanged
}

extension ConversationStreamEvent {

    /// Decodes a raw stream event into zero or more domain events. Pure and
    /// synchronous so it is unit-testable without the actor or a live stream;
    /// non-conversation events (test events, future types) decode to an empty array.
    public static func decode(_ event: Flipcash_Event_V1_Event) -> [ConversationStreamEvent] {
        guard case .chatUpdate(let update)? = event.type else { return [] }

        let conversationID = ConversationID(update.chat)
        var events: [ConversationStreamEvent] = []

        // The sequenced event log (message sent/edited/deleted).
        let chatEvents = update.events.events.map(DecodedChatEvent.init)
        if !chatEvents.isEmpty {
            events.append(.chatEvents(conversationID: conversationID, events: chatEvents))
        }

        for metadataUpdate in update.metadataUpdates {
            switch metadataUpdate.kind {
            case .fullRefresh(let refresh):
                events.append(.metadataRefresh(Conversation(refresh.metadata)))
            case .lastActivityChanged(let changed):
                events.append(.lastActivityChanged(conversationID: conversationID, date: changed.newLastActivity.date))
            case .viewerStateChanged(let changed):
                guard changed.hasViewerState else { break }
                events.append(.viewerStateChanged(conversationID: conversationID, viewerState: ConversationViewerState(changed.viewerState)))
            case .titleChanged(let changed):
                events.append(.titleChanged(conversationID: conversationID, title: changed.newTitle))
            case .descriptionChanged(let changed):
                events.append(.descriptionChanged(conversationID: conversationID, description: changed.newDescription))
            case .profilePictureChanged(let changed):
                // `ProfilePicture.init?` fails without an original rendition — required on the
                // wire, but treated the same as an absent picture rather than force-unwrapped.
                guard changed.hasNewProfilePicture, let picture = ProfilePicture(changed.newProfilePicture) else { break }
                events.append(.pictureChanged(conversationID: conversationID, picture: picture))
            case .coverPictureChanged(let changed):
                guard changed.hasNewCoverPicture, let coverPicture = ProfilePicture(changed.newCoverPicture) else { break }
                events.append(.coverPictureChanged(conversationID: conversationID, coverPicture: coverPicture))
            case .rulesChanged(let changed):
                guard changed.hasNewRules else { break }
                events.append(.rulesChanged(conversationID: conversationID, rules: ConversationRules(changed.newRules)))
            case .pinsChanged(let changed):
                guard changed.hasSummary else { break }
                let change: ConversationPinChange?
                switch changed.change {
                case .pinned(let pin): change = .pinned(ConversationPin(pin))
                case .unpinned(let messageID): change = .unpinned(MessageID(messageID))
                case nil: change = nil
                }
                events.append(.pinsChanged(conversationID: conversationID, change: change, summary: ConversationPinSummary(changed.summary)))
            case nil:
                break
            }
        }

        let readPointers: [MemberReadPointer] = update.pointerUpdates.pointers.compactMap { pointer in
            switch pointer.type {
            case .read:
                guard let userID = try? UUID(data: pointer.userID.value) else { return nil }
                return MemberReadPointer(userID: userID, value: MessageID(pointer.value), date: pointer.hasTs ? pointer.ts.date : nil)
            case .delivered, .sent, .unknown, .UNRECOGNIZED:
                return nil
            }
        }
        if !readPointers.isEmpty {
            events.append(.readPointersChanged(conversationID: conversationID, pointers: readPointers))
        }

        let typing = update.isTypingNotifications.isTypingNotifications.compactMap(TypingNotification.init)
        if !typing.isEmpty {
            events.append(.typingChanged(conversationID: conversationID, notifications: typing))
        }

        let rosterUpdates = update.rosterUpdates.rosterUpdates.compactMap(DecodedRosterUpdate.init)
        if !rosterUpdates.isEmpty {
            events.append(.rosterChanged(conversationID: conversationID, updates: rosterUpdates))
        }

        let reactionUpdates = update.reactionUpdates.reactionUpdates.compactMap(DecodedReactionUpdate.init)
        if !reactionUpdates.isEmpty {
            events.append(.reactionsChanged(conversationID: conversationID, updates: reactionUpdates))
        }

        let lobbyUpdates = update.lobbyUpdates.lobbyUpdates.compactMap(LobbyUpdate.init)
        if !lobbyUpdates.isEmpty {
            events.append(.lobbyChanged(conversationID: conversationID, updates: lobbyUpdates))
        }

        let paymentRequestUpdates = update.paymentRequestUpdates.paymentRequestUpdates.compactMap(DecodedPaymentRequestUpdate.init)
        if !paymentRequestUpdates.isEmpty {
            events.append(.paymentRequestsChanged(conversationID: conversationID, updates: paymentRequestUpdates))
        }

        return events
    }
}

extension DecodedChatEvent {
    /// Non-failable: an event whose mutations are all unrepresentable (e.g. a media message this client
    /// can't show) still carries a valid `sequence`/`count`, so the cursor must advance past it rather
    /// than gap-loop forever. `count` stays the server's value — the log advanced by it regardless of
    /// what the client can materialize.
    init(_ proto: Flipcash_Messaging_V1_Event) {
        self.init(
            sequence: proto.sequence,
            count: UInt64(proto.count),
            mutations: proto.mutations.compactMap(DecodedMutation.init)
        )
    }
}

extension DecodedMutation {
    /// Nil for a mutation whose message the client can't represent (unknown/media/reply content). A
    /// deleted message materializes as a `.deleted` tombstone via `ConversationMessage.init`.
    init?(_ proto: Flipcash_Messaging_V1_Mutation) {
        switch proto.type {
        case .messageSent(let proto):
            guard let message = ConversationMessage(proto) else { return nil }
            self = .sent(message)
        case .messageEdited(let proto):
            guard let message = ConversationMessage(proto) else { return nil }
            self = .edited(message)
        case .messageDeleted(let proto):
            guard let message = ConversationMessage(proto) else { return nil }
            self = .deleted(message)
        case .none:
            return nil
        }
    }
}

extension DecodedRosterUpdate {
    /// Nil when the update carries no roster summary (nothing to version-compare against) or its kind
    /// is not one this client knows about yet.
    init?(_ proto: Flipcash_Chat_V1_RosterUpdate) {
        guard proto.hasRosterSummary else { return nil }
        let rosterSummary = ConversationRosterSummary(proto.rosterSummary)
        switch proto.kind {
        case .memberJoined(let joined):
            let member = ConversationMember(joined.member)
            let chat = joined.hasMetadata ? Conversation(joined.metadata) : nil
            self.init(rosterSummary: rosterSummary, change: .joined(member: member, chat: chat))
        case .memberLeft(let left):
            guard let userID = try? UUID(data: left.userID.value) else { return nil }
            self.init(rosterSummary: rosterSummary, change: .left(userID: userID))
        case .membershipChanged:
            self.init(rosterSummary: rosterSummary, change: .membershipChanged)
        case nil:
            return nil
        }
    }
}
