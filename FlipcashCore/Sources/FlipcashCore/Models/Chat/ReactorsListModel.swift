//
//  ReactorsListModel.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Lists everyone who reacted to a message, one row per person with every emoji they used. The
/// server pages reactors one emoji at a time, so this pages every emoji's list and merges them.
/// Owns no UIKit/SwiftUI; the rules are exercised directly in tests.
@MainActor
@Observable
public final class ReactorsListModel {

    /// One person's reactions to the message — a row in the sheet.
    public struct Row: Identifiable, Equatable, Sendable {
        public let userID: UserID
        /// Every emoji they reacted with, in the message's pill order.
        public let emojis: [String]
        public var id: UserID { userID }

        public init(userID: UserID, emojis: [String]) {
            self.userID = userID
            self.emojis = emojis
        }
    }

    /// The rows loaded so far, newest reaction first. Updated once per round of pages rather than
    /// as each emoji's page lands, so a row never shows some of a person's emoji and then gains
    /// the rest.
    public private(set) var rows: [Row] = []

    private func mergedRows() -> [Row] {
        var latest: [UserID: Date] = [:]
        var reacted: [UserID: Set<String>] = [:]
        for emoji in emojis {
            for reactor in lists[emoji]?.reactors ?? [] {
                reacted[reactor.userID, default: []].insert(emoji)
                let date = reactor.reactedAt ?? .distantPast
                latest[reactor.userID] = max(latest[reactor.userID] ?? .distantPast, date)
            }
        }
        return reacted
            .map { userID, set in Row(userID: userID, emojis: emojis.filter(set.contains)) }
            .sorted { (latest[$0.userID] ?? .distantPast, $0.userID.uuidString) > (latest[$1.userID] ?? .distantPast, $1.userID.uuidString) }
    }

    /// Whether a page is in flight.
    public var isLoading: Bool { lists.values.contains(where: \.isLoading) }

    /// Whether any emoji has pages left to fetch.
    public var hasMore: Bool { emojis.contains { lists[$0]?.hasMore ?? true } }

    private struct List {
        var reactors: [Reactor] = []
        var nextPageToken: Data?
        var hasMore = true
        var isLoading = false
    }

    private var lists: [String: List] = [:]

    @ObservationIgnored private let emojis: [String]
    @ObservationIgnored private let source: any ReactorsSource
    @ObservationIgnored private let conversationID: ConversationID
    @ObservationIgnored private let messageID: MessageID

    /// `emojis` is every emoji on the message, in pill order.
    public init(source: any ReactorsSource, conversationID: ConversationID, messageID: MessageID, emojis: [String]) {
        self.source = source
        self.conversationID = conversationID
        self.messageID = messageID
        self.emojis = emojis
    }


    /// Fetches the next page of every emoji that has more, concurrently. Call once on open, then
    /// from the last visible row's `onAppear` for incremental paging.
    public func loadMoreIfNeeded() async {
        await withTaskGroup(of: Void.self) { group in
            for emoji in emojis {
                group.addTask { await self.loadMore(for: emoji) }
            }
        }
        rows = mergedRows()
    }

    private func loadMore(for emoji: String) async {
        var list = lists[emoji] ?? List()
        guard !list.isLoading, list.hasMore else { return }
        list.isLoading = true
        lists[emoji] = list
        let token = list.nextPageToken
        do {
            let page = try await source.fetchReactors(
                conversationID: conversationID,
                messageID: messageID,
                emoji: emoji,
                pagingToken: token
            )
            lists[emoji]?.reactors.append(contentsOf: page.reactors)
            lists[emoji]?.nextPageToken = page.nextPageToken
            lists[emoji]?.hasMore = page.nextPageToken != nil
        } catch {
            // A failed page leaves whatever loaded so far on screen and stops asking — there's no
            // retry affordance in the sheet, and a paging error is not one of the two reactions the
            // spec calls out for a toast.
            lists[emoji]?.hasMore = false
        }
        lists[emoji]?.isLoading = false
    }
}

extension Array where Element == ReactionPill {
    /// The reactors-sheet title count: every pill's count, summed — not the number of distinct
    /// reactors, since one person can react with more than one emoji.
    public var totalReactionCount: UInt64 {
        reduce(0) { $0 + $1.count }
    }
}
