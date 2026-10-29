//
//  ChatSearchModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.chat-search")

/// The query, chip and results of one Chats Search screen. The query lives only here, never on disk.
@MainActor
@Observable
final class ChatSearchModel {

    /// How many rows a section shows under All before its See all.
    static let allSectionLimit = 3

    /// What the current query matched, per chip.
    struct Results: Equatable {
        var chats: [Conversation] = []
        var currencies: [MintMetadata] = []
        var messages: [ChatSearchMessageHit] = []
        var links: [ChatSearchLink] = []

        static let empty = Results()
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            if isIdle { scope = .all }
            scheduleSearch()
        }
    }

    var scope: ChatSearchScope = .all

    private(set) var results: Results = .empty

    /// Whether the query is empty, so the screen shows Recent instead of results.
    var isIdle: Bool { ChatSearchQuery.normalized(query) == nil }

    /// Who shared each currency most recently, by mint.
    private(set) var currencySharers: [PublicKey: ChatSearchSharer] = [:]

    @ObservationIgnored private let conversations: () -> [Conversation]
    @ObservationIgnored private let loadMessages: () async throws -> [SearchableMessage]
    @ObservationIgnored private let currencySearch: any CurrencyNameSearching
    @ObservationIgnored private let chatName: (Conversation) -> String
    @ObservationIgnored private let chatHandles: (Conversation) -> [String]
    @ObservationIgnored private let senderName: (UUID, ConversationID) -> String?

    @ObservationIgnored private var messages: [SearchableMessage] = []
    @ObservationIgnored private var links: [ChatSearchLink] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        conversations: @escaping () -> [Conversation],
        loadMessages: @escaping () async throws -> [SearchableMessage],
        currencySearch: any CurrencyNameSearching,
        chatName: @escaping (Conversation) -> String,
        chatHandles: @escaping (Conversation) -> [String] = { _ in [] },
        senderName: @escaping (UUID, ConversationID) -> String?
    ) {
        self.conversations = conversations
        self.loadMessages = loadMessages
        self.currencySearch = currencySearch
        self.chatName = chatName
        self.chatHandles = chatHandles
        self.senderName = senderName
    }

    /// Reads the stored messages once for this screen, then reruns any query typed meanwhile.
    func load() async {
        do {
            messages = try await loadMessages()
        } catch {
            logger.error("Failed to load messages for chat search", metadata: ["error": "\(error)"])
        }
        links = ChatSearchLinks.links(in: messages)
        currencySharers = ChatSearchSharedCurrencies.sharers(in: messages)
        scheduleSearch(debounce: false)
    }

    /// Puts the screen back to a first open: empty query, All chip, no results. The messages read
    /// by `load()` stay, so the next query needs no reload.
    func reset() {
        searchTask?.cancel()
        query = ""
        scope = .all
        results = .empty
    }

    /// The name of the chat a result belongs to.
    func chatName(for conversationID: ConversationID) -> String? {
        conversations().first { $0.id == conversationID }.map(chatName)
    }

    /// Whether the chat a result belongs to is a group.
    func isGroup(_ conversationID: ConversationID) -> Bool {
        conversations().first { $0.id == conversationID }?.type == .group
    }

    /// "you" for the signed-in user's own messages, else the sender's name when one is known.
    func name(of senderID: UUID?, in conversationID: ConversationID) -> String? {
        senderID.flatMap { senderName($0, conversationID) }
    }

    private func scheduleSearch(debounce: Bool = true) {
        searchTask?.cancel()
        guard let query = ChatSearchQuery.normalized(query) else {
            results = .empty
            return
        }
        searchTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled, let self else { return }
            let found = await self.search(query)
            guard !Task.isCancelled else { return }
            self.results = found
        }
    }

    private func search(_ query: String) async -> Results {
        let chats = conversations().filter { conversation in
            !conversation.isHidden && ([chatName(conversation)] + chatHandles(conversation)).contains {
                ChatSearchQuery.matches($0, query)
            }
        }
        let messageHits = ChatSearchMessages.hits(in: messages, query: query)
        let linkHits = ChatSearchLinks.filter(links, query: query) { [self] link in
            [name(of: link.senderID, in: link.conversationID), chatName(for: link.conversationID)].compactMap { $0 }
        }
        let currencies: [MintMetadata]
        do {
            currencies = try await currencySearch.currencies(matching: query)
        } catch {
            logger.warning("Currency name search failed", metadata: ["error": "\(error)"])
            currencies = []
        }
        return Results(chats: chats, currencies: currencies, messages: messageHits, links: linkHits)
    }
}
