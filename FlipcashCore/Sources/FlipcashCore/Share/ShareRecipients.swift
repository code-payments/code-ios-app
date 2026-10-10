//
//  ShareRecipients.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The chats a share is addressed to, in the order they were picked, capped at ``limit``.
public struct ShareRecipientSelection: Equatable, Sendable {

    public enum ToggleResult: Equatable, Sendable {
        case selected
        case deselected
        /// The selection is full; nothing changed.
        case limitReached
    }

    public static let limit = 5

    public private(set) var ids: [ConversationID] = []

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var isFull: Bool { ids.count >= Self.limit }

    public func contains(_ id: ConversationID) -> Bool { ids.contains(id) }

    /// Selects `id`, or deselects it when already selected.
    @discardableResult
    public mutating func toggle(_ id: ConversationID) -> ToggleResult {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            return .deselected
        }
        guard !isFull else { return .limitReached }
        ids.append(id)
        return .selected
    }

    /// Selects `id` if there is room and it is not already selected.
    public mutating func select(_ id: ConversationID) {
        guard !contains(id) else { return }
        toggle(id)
    }

    /// Drops any selected id not in `available`.
    public mutating func retain(_ available: Set<ConversationID>) {
        ids.removeAll { !available.contains($0) }
    }
}

/// Searching and sectioning of the picker.
public enum ShareChatList {

    public struct Sections: Equatable, Sendable {
        /// Chats the Share sheet suggested; empty when there is no suggestion.
        public var suggested: [ConversationID]
        public var recent: [ConversationID]
        /// True when a search is active: `recent` then holds every match in one list.
        public var isSearching: Bool
    }

    /// Chats whose name contains `query`, ignoring case and diacritics, in their original order. A blank
    /// query matches everything.
    public static func filter(_ chats: [Conversation], query: String, name: (Conversation) -> String) -> [Conversation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chats }
        return chats.filter {
            name($0).range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The suggested chat first and the rest under "Recent chats", or, while searching, one flat list of
    /// matches. The suggested chat is not repeated in the recent list.
    public static func sections(
        _ chats: [Conversation],
        query: String,
        suggested: ConversationID?,
        name: (Conversation) -> String
    ) -> Sections {
        let matches = filter(chats, query: query, name: name).map(\.id)
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Sections(suggested: [], recent: matches, isSearching: true)
        }
        guard let suggested, matches.contains(suggested) else {
            return Sections(suggested: [], recent: matches, isSearching: false)
        }
        return Sections(suggested: [suggested], recent: matches.filter { $0 != suggested }, isSearching: false)
    }
}

/// Tracks which chats a share has reached, so a retry sends only to the rest.
public struct ShareSendProgress: Equatable, Sendable {

    public enum Status: Equatable, Sendable {
        case pending
        case sent
        case failed(message: String, canRetry: Bool)
    }

    public private(set) var statuses: [ConversationID: Status]
    public let order: [ConversationID]

    public init(recipients: [ConversationID]) {
        order = recipients
        statuses = Dictionary(uniqueKeysWithValues: recipients.map { ($0, .pending) })
    }

    public mutating func markSent(_ id: ConversationID) { statuses[id] = .sent }

    public mutating func markFailed(_ id: ConversationID, message: String, canRetry: Bool) {
        statuses[id] = .failed(message: message, canRetry: canRetry)
    }

    /// Recipients still to send to: pending, or failed with a retryable error.
    public var remaining: [ConversationID] {
        order.filter {
            switch statuses[$0] {
            case .pending, .failed(_, canRetry: true): true
            case .sent, .failed(_, canRetry: false), nil: false
            }
        }
    }

    public var failed: [ConversationID] {
        order.filter { if case .failed = statuses[$0] { true } else { false } }
    }

    public var isComplete: Bool { order.allSatisfy { statuses[$0] == .sent } }

    /// True when something failed and nothing retryable is left to try.
    public var isStuck: Bool { !isComplete && remaining.isEmpty }
}
