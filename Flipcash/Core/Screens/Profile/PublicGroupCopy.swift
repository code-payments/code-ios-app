//
//  PublicGroupCopy.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashStore

/// The words the public group profile shows.
enum PublicGroupCopy {

    /// The line under the group's name: "Public group · 22 members", or "Public group" before the
    /// count is known.
    static func summary(memberCount: UInt64?) -> String {
        guard let memberCount, memberCount > 0 else { return "Public group" }
        return "Public group · \(PrivateGroupCopy.memberCount(memberCount))"
    }

    /// The pulse card's headline: "6 chatting this week", or "Quiet this week" when nobody is.
    static func chatting(count: Int) -> String {
        count > 0 ? "\(count) chatting this week" : "Quiet this week"
    }

    /// How long ago the last message was: "just now", "2m ago", "3h ago", "1 day ago" or "12 days ago".
    static func lastMessage(at date: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        switch minutes {
        case ..<1:           return "just now"
        case ..<60:          return "\(minutes)m ago"
        case ..<(60 * 24):   return "\(minutes / 60)h ago"
        default:
            let days = minutes / (60 * 24)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    /// The pulse card's meta line: "Last message 2m ago · 22 members", leaving out whichever part
    /// isn't known, and `nil` when neither is.
    static func pulseMeta(lastMessageAt: Date?, memberCount: UInt64?, now: Date) -> String? {
        var parts: [String] = []
        if let lastMessageAt {
            parts.append("Last message \(lastMessage(at: lastMessageAt, now: now))")
        }
        if let memberCount, memberCount > 0 {
            parts.append(PrivateGroupCopy.memberCount(memberCount))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What a public group's pulse card says about the last week of chat, read from the server's
/// sample of at most 100 chatters rather than the full roster.
nonisolated struct PublicGroupPulse: Equatable {

    /// The faces the card draws at most.
    static let faceLimit = 5

    /// How far back "this week" reaches.
    static let window: TimeInterval = 7 * 24 * 60 * 60

    /// The people who chatted this week, newest first, up to ``faceLimit``.
    let faces: [GroupPortrait]
    /// How many sampled chatters sent a message within the window.
    let chattingCount: Int
    /// When the most recent sampled message was sent, even if it falls outside the window.
    let lastMessageAt: Date?

    /// How many chatters the facepile doesn't show.
    var overflow: Int { max(chattingCount - faces.count, 0) }

    /// The pulse of `chatters` as of `now`.
    init(chatters: [SampledChatter], now: Date) {
        let cutoff = now.addingTimeInterval(-Self.window)
        let recent = chatters
            .filter { ($0.lastSentAt ?? .distantPast) >= cutoff }
            .sorted { ($0.lastSentAt ?? .distantPast) > ($1.lastSentAt ?? .distantPast) }
        faces = recent.prefix(Self.faceLimit).map(GroupPortrait.init)
        chattingCount = recent.count
        lastMessageAt = chatters.compactMap(\.lastSentAt).max()
    }
}

/// A token a requirement names, for the tile's "of ◉ Jeffy".
nonisolated struct PublicGroupToken: Equatable {
    /// The token's mint, which opens its info page.
    let mint: PublicKey
    /// The token's display name.
    let name: String
    /// The token's logo, when it has one.
    let imageURL: URL?
}

/// One tile of the requirements card: the amount to hold and what it is for.
nonisolated struct PublicGroupRequirementTile: Identifiable, Equatable {

    enum Purpose: Equatable {
        case joinAndChat, join, chat

        /// The caption under the amount.
        var caption: String {
            switch self {
            case .joinAndChat:  "to join and chat"
            case .join:         "to join"
            case .chat:         "to chat"
            }
        }
    }

    let purpose: Purpose
    /// The amount, as the gate panel words it and restated in the display currency: "$100".
    let amount: String
    /// The token the amount is held in; `nil` for a dollar-token or any-holding rule, or one whose
    /// name isn't known.
    let token: PublicGroupToken?

    var id: Purpose { purpose }

    /// The tiles for `requirements`, with amounts in `display`: one reading "to join and chat" when
    /// both rules are the same amount in the same tokens, else one per rule.
    // On the main actor, where the app's `GroupBalanceRequirements.formatted` lives.
    @MainActor
    static func tiles(
        for requirements: GroupBalanceRequirements,
        metadata: [PublicKey: StoredMintMetadata],
        display: DisplayCurrency
    ) -> [PublicGroupRequirementTile] {
        if let join = requirements.join, join == requirements.chat {
            return [tile(.joinAndChat, join, metadata, display)]
        }
        var tiles: [PublicGroupRequirementTile] = []
        if let join = requirements.join { tiles.append(tile(.join, join, metadata, display)) }
        if let chat = requirements.chat { tiles.append(tile(.chat, chat, metadata, display)) }
        return tiles
    }

    @MainActor
    private static func tile(
        _ purpose: Purpose,
        _ requirement: MinimumBalanceRequirement,
        _ metadata: [PublicKey: StoredMintMetadata],
        _ display: DisplayCurrency
    ) -> PublicGroupRequirementTile {
        var token: PublicGroupToken?
        if let mint = requirement.mints.first, mint != .usdf, let stored = metadata[mint] {
            token = PublicGroupToken(mint: mint, name: stored.name, imageURL: stored.imageURL)
        }
        return PublicGroupRequirementTile(
            purpose: purpose,
            // No token name: the tile names the token beside the amount.
            amount: GroupBalanceRequirements.formatted(requirement, mintName: nil, in: display),
            token: token
        )
    }
}
