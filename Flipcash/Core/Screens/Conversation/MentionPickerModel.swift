//
//  MentionPickerModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import FlipcashCore
import CoreGraphics
import Observation

/// The members a group chat's mention picker offers for the `@word` being typed, for one visit to
/// the chat.
@MainActor @Observable
final class MentionPickerModel {

    /// The most matches asked of the search. The list shows a few and scrolls through the rest.
    static let searchLimit = 20

    /// The members to offer, best first. Empty while the picker is closed or nothing matches.
    private(set) var candidates: [ConversationMember] = []

    /// The transcript's height without the list, as the chat screen last measured it.
    var room: CGFloat?

    @ObservationIgnored private let source: any RosterSearchSource
    @ObservationIgnored private let chatID: ConversationID
    /// The text after the `@` being searched for, or `nil` while the picker is closed.
    @ObservationIgnored private var query: String?
    @ObservationIgnored private var didRefresh = false

    /// The search for the current query, cancelled when the query changes.
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    /// The once-per-visit prepare of the source, which re-runs the current query when it lands.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

    init(source: any RosterSearchSource, chatID: ConversationID) {
        self.source = source
        self.chatID = chatID
    }

    deinit {
        searchTask?.cancel()
        refreshTask?.cancel()
    }

    /// Searches for `query`, the text after the `@`, or closes the picker when it is `nil`.
    func update(query: String?) {
        guard query != self.query else { return }
        self.query = query
        searchTask?.cancel()
        guard let query else {
            searchTask = nil
            if !candidates.isEmpty { candidates = [] }
            return
        }
        if !didRefresh {
            didRefresh = true
            refreshTask = Task { [source, chatID] in
                await source.prepare(chatID: chatID)
                guard !Task.isCancelled else { return }
                // New joiners appear without another keystroke.
                self.rerun()
            }
        }
        run(query)
    }

    private func rerun() {
        guard let query else { return }
        searchTask?.cancel()
        run(query)
    }

    private func run(_ query: String) {
        searchTask = Task { [source, chatID] in
            let matches = (try? await source.search(chatID: chatID, query: query, limit: Self.searchLimit)) ?? []
            guard !Task.isCancelled, self.query == query else { return }
            // A pick writes `@username`, so a member without one has nothing to insert.
            let members = matches.map(\.member).filter { $0.username != nil }
            if members != candidates { candidates = members }
        }
    }
}
