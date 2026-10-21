//
//  ChatSearch.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore

/// The chips pinned above Chats Search results.
nonisolated enum ChatSearchScope: CaseIterable, Hashable {
    case all
    case chats
    case currencies
    case messages
    case links

    var title: String {
        switch self {
        case .all:        "All"
        case .chats:      "Chats"
        case .currencies: "Currencies"
        case .messages:   "Messages"
        case .links:      "Links"
        }
    }
}

/// The matching rule every Chats Search chip shares.
nonisolated enum ChatSearchQuery {

    /// The query to match on, or nil when there is nothing to search for.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether `text` contains `query`, ignoring case and diacritics.
    static func matches(_ text: String?, _ query: String) -> Bool {
        guard let text else { return false }
        return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

// MARK: - Messages -

/// A message whose searchable text matched the query.
nonisolated struct ChatSearchMessageHit: Identifiable, Hashable {
    let conversationID: ConversationID
    let messageID: MessageID
    let senderID: UUID?
    let date: Date
    let text: String

    var id: String { "\(conversationID.description)-\(messageID.value)" }
}

nonisolated enum ChatSearchMessages {

    /// The user-authored text a message can be found by: its body, a media caption, or a shared
    /// profile's handle. Nil for content with no such text.
    static func searchableText(of message: ConversationMessage) -> String? {
        switch message.content {
        case .text(let text):
            text.isEmpty ? nil : text
        case .media(_, let caption):
            caption.flatMap { $0.isEmpty ? nil : $0 }
        case .widget(.shareProfile(let widget)):
            widget.username.value
        case .widget(.unrecognized), .cash, .deleted, .encrypted, .system:
            nil
        }
    }

    /// The messages in `messages` whose searchable text contains `query`, in the order given.
    static func hits(in messages: [SearchableMessage], query: String) -> [ChatSearchMessageHit] {
        messages.compactMap { item in
            guard let text = searchableText(of: item.message), ChatSearchQuery.matches(text, query) else {
                return nil
            }
            return ChatSearchMessageHit(
                conversationID: item.conversationID,
                messageID: item.message.id,
                senderID: item.message.senderID,
                date: item.message.date,
                text: text
            )
        }
    }
}

// MARK: - Links -

/// An outside web link someone shared in a chat.
nonisolated struct ChatSearchLink: Identifiable, Hashable {
    let url: URL
    let host: String
    /// The title the sender's link preview carried, when it was for this URL.
    let title: String?
    let conversationID: ConversationID
    let messageID: MessageID
    let senderID: UUID?
    let date: Date

    var id: URL { url }
}

nonisolated enum ChatSearchLinks {

    /// Whether a link found in message text belongs under Links. Every Flipcash link is left out:
    /// cash links, group invites and chat links, tip card and profile links, currency links, and the
    /// login and verification links that carry secrets. A jump wrapper is judged by both the wrapper
    /// and its target.
    static func isListed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        for candidate in [url, Route.unwrappingJump(url)].compactMap({ $0 }) {
            guard let host = candidate.host()?.lowercased() else { return false }
            if Route.flipcashHosts.contains(host) { return false }
        }
        return true
    }

    /// Every listed link in the text messages of `messages`, one per URL, keeping the first share
    /// met. Pass messages newest first to keep the newest share.
    static func links(in messages: [SearchableMessage]) -> [ChatSearchLink] {
        var seen = Set<URL>()
        var links: [ChatSearchLink] = []
        for item in messages {
            guard case .text(let text) = item.message.content else { continue }
            for detected in LinkDetector().webLinks(in: text) where isListed(detected.url) {
                guard seen.insert(detected.url).inserted, let host = detected.url.host() else { continue }
                let preview = item.message.linkPreview
                links.append(ChatSearchLink(
                    url: detected.url,
                    host: host.lowercased().replacingOccurrences(of: "www.", with: "", options: .anchored),
                    title: preview.flatMap { URL(string: $0.url) == detected.url ? $0.title : nil },
                    conversationID: item.conversationID,
                    messageID: item.message.id,
                    senderID: item.message.senderID,
                    date: item.message.date
                ))
            }
        }
        return links
    }

    /// The links in `links` whose URL, title, or the names `names` gives them (sharer, chat)
    /// contain `query`.
    static func filter(_ links: [ChatSearchLink], query: String, names: (ChatSearchLink) -> [String]) -> [ChatSearchLink] {
        links.filter { link in
            ChatSearchQuery.matches(link.url.absoluteString, query)
                || ChatSearchQuery.matches(link.title, query)
                || names(link).contains { ChatSearchQuery.matches($0, query) }
        }
    }
}

// MARK: - Shared currencies -

/// Who shared a currency, and the chat they shared it in.
nonisolated struct ChatSearchSharer: Hashable {
    let senderID: UserID
    let conversationID: ConversationID
}

nonisolated enum ChatSearchSharedCurrencies {

    /// The sender of the newest message linking each currency's page, by mint. Pass messages
    /// newest first.
    static func sharers(in messages: [SearchableMessage]) -> [PublicKey: ChatSearchSharer] {
        var sharers: [PublicKey: ChatSearchSharer] = [:]
        for item in messages {
            guard case .text(let text) = item.message.content,
                  text.localizedCaseInsensitiveContains("/token/"),
                  let senderID = item.message.senderID else { continue }
            for detected in LinkDetector().webLinks(in: text) {
                let target = Route.unwrappingJump(detected.url) ?? detected.url
                guard let host = target.host()?.lowercased(), Route.flipcashHosts.contains(host),
                      let route = Route(url: target), case .token(let mint) = route.path,
                      sharers[mint] == nil else { continue }
                sharers[mint] = ChatSearchSharer(senderID: senderID, conversationID: item.conversationID)
            }
        }
        return sharers
    }
}
