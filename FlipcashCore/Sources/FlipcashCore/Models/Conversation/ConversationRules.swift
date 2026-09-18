//
//  ConversationRules.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Summary of a chat's roster — its member list — without containing it: what
/// a client needs to know whether its copy of ``Conversation/members`` is
/// stale, without holding the full list. See `chat.v1.RosterSummary`.
public struct ConversationRosterSummary: Hashable, Sendable {

    /// True number of currently joined members. ``Conversation/members`` is
    /// only a subset for a large group chat; this is its real size.
    public let memberCount: UInt64

    /// Opaque version, advanced by exactly one on every change to the
    /// membership records (a join, a leave, or a future per-member change
    /// such as a role) and never on an idempotent no-op or a profile change.
    ///
    /// Compare against the last value seen: a different value means the
    /// cached member list may be stale and should be refetched. On a stream,
    /// apply a greater value and drop the rest — delivery order does not
    /// matter. There is no delta to fetch against it, only a refetch of the
    /// members.
    public let version: UInt64

    public init(memberCount: UInt64, version: UInt64) {
        self.memberCount = memberCount
        self.version = version
    }
}

extension ConversationRosterSummary {
    public init(_ proto: Flipcash_Chat_V1_RosterSummary) {
        self.init(memberCount: proto.memberCount, version: proto.version)
    }
}

/// The signed-in user's per-viewer state for a chat — currently just mute status. See
/// `chat.v1.ViewerState`.
public struct ConversationViewerState: Hashable, Sendable {

    /// Present iff the chat is muted for the viewer. Muted pushes are still delivered (so the
    /// client can store the message) but flagged for the client to suppress the notification.
    public let mute: ConversationMuteState?

    /// Opaque version, advanced by exactly one on every real change. Compared like
    /// ``ConversationRosterSummary/version``: apply the greater value and drop the rest — delivery
    /// order does not matter, and there is no delta to fetch, only a refetch.
    public let version: UInt64

    public init(mute: ConversationMuteState? = nil, version: UInt64 = 0) {
        self.mute = mute
        self.version = version
    }
}

extension ConversationViewerState {
    public init(_ proto: Flipcash_Chat_V1_ViewerState) {
        self.init(
            mute: (proto.hasSettings && proto.settings.hasMute) ? ConversationMuteState(proto.settings.mute) : nil,
            version: proto.version
        )
    }
}

/// Whether, and until when, the signed-in user has muted a chat. See `chat.v1.MuteState`.
public enum ConversationMuteState: Hashable, Sendable {
    /// Muted until this date, after which the mute lapses client-side. Nothing is sent when it
    /// does, so the client owns the countdown.
    case until(Date)
    /// Muted forever, until explicitly unmuted.
    case forever
}

extension ConversationMuteState {
    /// Falls back to `.forever` when `duration` is unset — defensive only: the server never sends
    /// a `MuteState` without one, since its presence on `Settings.mute` is itself the mute signal.
    init(_ proto: Flipcash_Chat_V1_MuteState) {
        switch proto.duration {
        case .until(let timestamp):
            self = .until(timestamp.date)
        case .forever, nil:
            self = .forever
        }
    }

    /// Builds the wire form for `MuteChatRequest.mute`.
    var proto: Flipcash_Chat_V1_MuteState {
        .with {
            switch self {
            case .until(let date):
                $0.until = .init(date: date)
            case .forever:
                $0.forever = .init()
            }
        }
    }
}

/// Requirements a user must satisfy to participate in a group chat. Only
/// ever set for group chats; unset means the chat has no participation
/// requirements. See `chat.v1.Rules`.
public struct ConversationRules: Hashable, Codable, Sendable {

    /// Requirements to read and join the chat. Empty means anyone can.
    public var listener: [ConversationListenerRule]

    /// Requirements to send messages in the chat, applied in addition to
    /// ``listener`` — a user must be able to listen before they can speak.
    /// Empty means any member can send.
    public var speaker: [ConversationSpeakerRule]

    public init(listener: [ConversationListenerRule] = [], speaker: [ConversationSpeakerRule] = []) {
        self.listener = listener
        self.speaker = speaker
    }
}

extension ConversationRules {
    public init(_ proto: Flipcash_Chat_V1_Rules) {
        self.init(
            listener: proto.listener.compactMap(ConversationListenerRule.init),
            speaker: proto.speaker.compactMap(ConversationSpeakerRule.init)
        )
    }
}

extension ConversationRules {
    /// Builds the wire form for `StartChatRequest.GroupChatParameters.rules`.
    var proto: Flipcash_Chat_V1_Rules {
        .with {
            $0.listener = listener.map(\.proto)
            $0.speaker = speaker.map(\.proto)
        }
    }
}

/// A single requirement gating reading and joining a chat. See
/// `chat.v1.ListenerRules`.
public enum ConversationListenerRule: Hashable, Codable, Sendable {
    case minimumBalance(MinimumBalanceRequirement)
    case staff
}

extension ConversationListenerRule {
    /// Returns nil when `proto` carries neither arm of the `kind` oneof, or a
    /// `minimumBalance` requirement in a currency this client doesn't
    /// recognize.
    init?(_ proto: Flipcash_Chat_V1_ListenerRules) {
        switch proto.kind {
        case .minimumBalance(let requirement):
            guard let requirement = MinimumBalanceRequirement(requirement) else { return nil }
            self = .minimumBalance(requirement)
        case .staff:
            self = .staff
        case nil:
            return nil
        }
    }
}

extension ConversationListenerRule {
    var proto: Flipcash_Chat_V1_ListenerRules {
        .with {
            switch self {
            case .minimumBalance(let requirement):
                $0.minimumBalance = requirement.proto
            case .staff:
                $0.staff = .init()
            }
        }
    }
}

/// A single requirement gating sending messages in a chat. See
/// `chat.v1.SpeakerRules`.
public enum ConversationSpeakerRule: Hashable, Codable, Sendable {
    case minimumBalance(MinimumBalanceRequirement)
    case staff
}

extension ConversationSpeakerRule {
    /// Returns nil when `proto` carries neither arm of the `kind` oneof, or a
    /// `minimumBalance` requirement in a currency this client doesn't
    /// recognize.
    init?(_ proto: Flipcash_Chat_V1_SpeakerRules) {
        switch proto.kind {
        case .minimumBalance(let requirement):
            guard let requirement = MinimumBalanceRequirement(requirement) else { return nil }
            self = .minimumBalance(requirement)
        case .staff:
            self = .staff
        case nil:
            return nil
        }
    }
}

extension ConversationSpeakerRule {
    var proto: Flipcash_Chat_V1_SpeakerRules {
        .with {
            switch self {
            case .minimumBalance(let requirement):
                $0.minimumBalance = requirement.proto
            case .staff:
                $0.staff = .init()
            }
        }
    }
}

/// Requires holding a minimum balance, denominated in fiat, in an acceptable
/// mint. See `chat.v1.MinimumBalanceRequirement`.
public struct MinimumBalanceRequirement: Hashable, Codable, Sendable {

    /// The minimum balance, denominated in fiat.
    public let amount: FiatAmount

    /// The mints the balance may be held in. Empty means the requirement
    /// applies across all mints; otherwise it applies only to the one listed
    /// mint. Repeated so multiple mints can be specified in the future.
    public let mints: [PublicKey]

    public init(amount: FiatAmount, mints: [PublicKey] = []) {
        self.amount = amount
        self.mints = mints
    }
}

extension MinimumBalanceRequirement {
    /// Returns nil for a currency code this client doesn't recognize.
    /// Malformed mint entries are dropped individually rather than failing
    /// the whole requirement.
    init?(_ proto: Flipcash_Chat_V1_MinimumBalanceRequirement) {
        guard let currency = CurrencyCode(rawValue: proto.amount.currency.lowercased()) else {
            return nil
        }
        self.init(
            amount: FiatAmount(value: Decimal(proto.amount.nativeAmount), currency: currency),
            mints: proto.mints.compactMap { try? PublicKey($0.value) }
        )
    }
}

extension MinimumBalanceRequirement {
    var proto: Flipcash_Chat_V1_MinimumBalanceRequirement {
        .with {
            $0.amount = .with {
                $0.currency = amount.currency.rawValue
                $0.nativeAmount = amount.doubleValue
            }
            $0.mints = mints.map { mint in .with { $0.value = mint.data } }
        }
    }
}
