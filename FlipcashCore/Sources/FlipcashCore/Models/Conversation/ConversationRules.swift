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

/// Requirements a user must satisfy to participate in a group chat. Only
/// ever set for group chats; unset means the chat has no participation
/// requirements. See `chat.v1.Rules`.
public struct ConversationRules: Hashable, Sendable {

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

/// A single requirement gating reading and joining a chat. See
/// `chat.v1.ListenerRules`.
public enum ConversationListenerRule: Hashable, Sendable {
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

/// A single requirement gating sending messages in a chat. See
/// `chat.v1.SpeakerRules`.
public enum ConversationSpeakerRule: Hashable, Sendable {
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

/// Requires holding a minimum balance, denominated in fiat, in an acceptable
/// mint. See `chat.v1.MinimumBalanceRequirement`.
public struct MinimumBalanceRequirement: Hashable, Sendable {

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
