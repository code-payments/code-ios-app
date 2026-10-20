//
//  ChatSearchTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore
import FlipcashStore

@MainActor
@Suite("Chats Search")
struct ChatSearchTests {

    private let dm = ConversationID(data: Data(repeating: 1, count: 32))
    private let group = ConversationID(data: Data(repeating: 2, count: 32))
    private let jeff = UUID()

    private static let mintA = try! PublicKey(base58: "ccJYP5gjZqcEHaphcxAZvkxCrnTVfYMjyhSYkpQtf8Z")
    private static let mintB = try! PublicKey(base58: "pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F")

    private func message(
        _ id: UInt64,
        in conversationID: ConversationID? = nil,
        content: ConversationMessage.Content,
        linkPreview: MessageLinkPreview? = nil
    ) -> SearchableMessage {
        SearchableMessage(
            conversationID: conversationID ?? dm,
            message: ConversationMessage(
                id: MessageID(value: id),
                senderID: jeff,
                content: content,
                date: Date(timeIntervalSince1970: Double(id)),
                unreadSeq: 0,
                linkPreview: linkPreview
            )
        )
    }

    private func text(_ id: UInt64, _ body: String, in conversationID: ConversationID? = nil) -> SearchableMessage {
        message(id, in: conversationID, content: .text(body))
    }

    // MARK: - Query

    @Test("A blank or whitespace query is nothing to search for")
    func blankQuery() {
        #expect(ChatSearchQuery.normalized("") == nil)
        #expect(ChatSearchQuery.normalized("  \n") == nil)
        #expect(ChatSearchQuery.normalized("  jeff ") == "jeff")
    }

    @Test("Matching ignores case and diacritics")
    func matchingFolds() {
        #expect(ChatSearchQuery.matches("Jeffy Holders", "jEFF"))
        #expect(ChatSearchQuery.matches("Café", "cafe"))
        #expect(!ChatSearchQuery.matches("Raul", "jeff"))
        #expect(!ChatSearchQuery.matches(nil, "jeff"))
    }

    // MARK: - Links

    @Test(
        "Every Flipcash link is left out of Links",
        arguments: [
            "https://send.flipcash.com/c/#/e=3xyzABC",
            "https://app.flipcash.com/cash/#/e=3xyzABC",
            "https://app.flipcash.com/login/#/e=3xyzABC",
            "https://app.flipcash.com/verify?code=123",
            "https://app.flipcash.com/token/ccJYP5gjZqcEHaphcxAZvkxCrnTVfYMjyhSYkpQtf8Z",
            "https://flipcash.com/jeff",
            "https://www.flipcash.com/jeff",
            "https://flipcash.com/6E8D0A6C-2D6F-4E44-9A4B-8D5C1A0F1F11",
            "https://flipcash.com/tip/6E8D0A6C-2D6F-4E44-9A4B-8D5C1A0F1F11",
            "https://flipcash.com/chat/6E8D0A6C-2D6F-4E44-9A4B-8D5C1A0F1F11",
            "HTTPS://APP.FLIPCASH.COM/chat/abc",
            "https://jump.flipcash.com/#source=https%3A%2F%2Fapp.flipcash.com%2Ftoken%2Fabc",
            "flipcash://give",
        ]
    )
    func flipcashLinksExcluded(_ string: String) throws {
        #expect(!ChatSearchLinks.isListed(try #require(URL(string: string))))
    }

    @Test("Links built by the app's own builders are left out")
    func builtLinksExcluded() {
        let username = Username("jeff")
        #expect(!ChatSearchLinks.isListed(URL.tipcard(for: jeff, username: username)))
        #expect(!ChatSearchLinks.isListed(URL.tipcard(for: jeff, username: nil)))
        #expect(!ChatSearchLinks.isListed(URL.groupChatInvite(for: group)))
        #expect(!ChatSearchLinks.isListed(URL.messageLink(in: group, messageID: MessageID(value: 4))))
        #expect(!ChatSearchLinks.isListed(URL.chatDeepLink(for: group)))
    }

    @Test("Outside web links are listed, including look-alike hosts")
    func webLinksListed() throws {
        #expect(ChatSearchLinks.isListed(try #require(URL(string: "https://github.com/code-payments/flipcash-program"))))
        #expect(ChatSearchLinks.isListed(try #require(URL(string: "http://x.com/jeff"))))
        #expect(ChatSearchLinks.isListed(try #require(URL(string: "https://notflipcash.com/c/#/e=abc"))))
    }

    @Test("Links come from text messages only, one row per URL keeping the first share given")
    func linksFromMessages() {
        let messages = [
            text(9, "again https://github.com/code-payments/flipcash-program"),
            text(8, "send https://send.flipcash.com/c/#/e=abc and https://x.com/jeff/status/1"),
            text(7, "first https://github.com/code-payments/flipcash-program", in: group),
            message(6, content: .media([], caption: "https://youtube.com/watch?v=1")),
        ]
        let links = ChatSearchLinks.links(in: messages)

        #expect(links.map(\.url.absoluteString) == [
            "https://github.com/code-payments/flipcash-program",
            "https://x.com/jeff/status/1",
        ])
        #expect(links[0].messageID == MessageID(value: 9))
        #expect(links[0].conversationID == dm)
        #expect(links[1].host == "x.com")
    }

    @Test("A link takes its preview's title only when the preview is for that URL")
    func previewTitle() {
        let preview = MessageLinkPreview(url: "https://x.com/jeff", title: "Jeff on holders", description: nil, image: nil)
        let links = ChatSearchLinks.links(in: [
            message(1, content: .text("https://x.com/jeff https://www.youtube.com/watch?v=1"), linkPreview: preview),
        ])
        #expect(links.map(\.title) == ["Jeff on holders", nil])
        #expect(links[1].host == "youtube.com")
    }

    @Test("Links filter on URL, title, and the sharer and chat names")
    func linkFilter() {
        let preview = MessageLinkPreview(url: "https://substack.com/p/1", title: "Why every creator needs a currency", description: nil, image: nil)
        let links = ChatSearchLinks.links(in: [
            text(3, "https://github.com/code-payments/flipcash-program", in: group),
            message(2, content: .text("https://substack.com/p/1"), linkPreview: preview),
            text(1, "https://example.com/jeff"),
        ])
        let names: (ChatSearchLink) -> [String] = { $0.conversationID == self.group ? ["Jeffy Holders"] : ["Erik"] }

        #expect(ChatSearchLinks.filter(links, query: "jeff", names: names).map(\.messageID.value) == [3, 1])
        #expect(ChatSearchLinks.filter(links, query: "creator", names: names).map(\.messageID.value) == [2])
        #expect(ChatSearchLinks.filter(links, query: "erik", names: names).map(\.messageID.value) == [2, 1])
    }

    // MARK: - Messages

    @Test("Messages match text, media captions and shared profile handles, never cash or deleted rows")
    func messageHits() {
        let messages = [
            text(5, "did jeff ever send the link?"),
            message(4, content: .media([], caption: "Jeff at the meetup")),
            message(3, content: .widget(.shareProfile(ShareProfileWidget(username: Username("jeffy")!)))),
            message(2, content: .deleted(.init(deletedBy: nil, deletedAt: .now))),
            text(1, "nothing to see"),
        ]
        let hits = ChatSearchMessages.hits(in: messages, query: "JEFF")
        #expect(hits.map(\.messageID.value) == [5, 4, 3])
        #expect(hits.map(\.text) == ["did jeff ever send the link?", "Jeff at the meetup", "jeffy"])
    }

    // MARK: - Currencies

    private func mint(_ address: PublicKey, name: String, symbol: String = "TEST", withMetrics: Bool = false) -> MintMetadata {
        let base = MintMetadata.makeLaunchpad(address: address, name: name)
        return MintMetadata(
            address: base.address,
            decimals: base.decimals,
            name: name,
            symbol: symbol,
            description: base.description,
            imageURL: nil,
            vmMetadata: base.vmMetadata,
            launchpadMetadata: base.launchpadMetadata,
            holderMetrics: withMetrics ? HolderMetrics(currentHolders: 100, holderDeltas: [.init(range: .lastWeek, delta: 41)]) : nil,
            marketCapMetrics: withMetrics ? MarketCapMetrics(currentMarketCap: 48_200, marketCapDeltas: [.init(range: .lastWeek, delta: 3_100)]) : nil
        )
    }

    @Test("Currencies match name or symbol, ignoring case")
    func currencyFilter() {
        let candidates = [
            mint(Self.mintA, name: "Jeffy"),
            mint(Self.mintB, name: "Raul Coin", symbol: "JEFF"),
        ]
        #expect(LocalCurrencyNameSearch.filter(candidates, query: "jeff").map(\.name) == ["Jeffy", "Raul Coin"])
        #expect(LocalCurrencyNameSearch.filter(candidates, query: "raul").map(\.name) == ["Raul Coin"])
        #expect(LocalCurrencyNameSearch.filter(candidates, query: "zzz").isEmpty)
    }

    @Test("A currency both held and discovered appears once, with Discover's metrics")
    func currencyDedupe() {
        let held = mint(Self.mintA, name: "Jeffy")
        let discovered = mint(Self.mintA, name: "Jeffy", withMetrics: true)
        let found = LocalCurrencyNameSearch.filter([held, discovered], query: "jeffy")

        #expect(found.count == 1)
        #expect(found.first?.marketCapMetrics?.currentMarketCap == 48_200)
    }

    @Test("USDF never appears under Currencies")
    func usdfExcluded() {
        #expect(LocalCurrencyNameSearch.filter([.usdf], query: MintMetadata.usdf.name).isEmpty)
    }

    @Test("The search goes through the protocol so a server search can stand in")
    func currencySearchProtocol() async throws {
        let candidates = [mint(Self.mintA, name: "Jeffy")]
        let search: any CurrencyNameSearching = LocalCurrencyNameSearch(candidates: { candidates })
        #expect(try await search.currencies(matching: "jef").map(\.name) == ["Jeffy"])
    }

    @Test("A currency card shows weekly change and new members only from Discover's weekly metrics")
    func currencyCardLines() {
        let withMetrics = mint(Self.mintA, name: "Jeffy", withMetrics: true)
        #expect(SearchCurrencyCard.marketCap(of: withMetrics) == 48_200)
        #expect(SearchCurrencyCard.weeklyChange(of: withMetrics) == "+$3.1K this week")
        #expect(SearchCurrencyCard.newMembers(of: withMetrics) == "+41 members")

        let held = mint(Self.mintA, name: "Jeffy")
        #expect(SearchCurrencyCard.weeklyChange(of: held) == nil)
        #expect(SearchCurrencyCard.newMembers(of: held) == nil)
    }

    @Test("A currency's sharer is the sender of the newest message linking its page")
    func currencySharers() {
        let erik = UUID()
        let older = SearchableMessage(
            conversationID: group,
            message: ConversationMessage(id: MessageID(value: 1), senderID: erik, content: .text("https://app.flipcash.com/token/\(Self.mintA.base58)"), date: .distantPast, unreadSeq: 0)
        )
        let newer = text(2, "look https://app.flipcash.com/token/\(Self.mintA.base58)")
        let sharers = ChatSearchSharedCurrencies.sharers(in: [newer, older])

        #expect(sharers[Self.mintA] == ChatSearchSharer(senderID: jeff, conversationID: dm))
        #expect(sharers[Self.mintB] == nil)
    }

    // MARK: - Recent

    @Test("Recent puts the newest chat first, moves a repeat to the front, and keeps at most ten")
    func recentOrdering() {
        let ids = (0..<12).map { ConversationID(data: Data(repeating: UInt8($0), count: 32)) }
        var recents: [ConversationID] = []
        for id in ids { recents = ChatSearchRecents.recording(id, in: recents) }

        #expect(recents.count == ChatSearchRecents.limit)
        #expect(recents.first == ids[11])

        recents = ChatSearchRecents.recording(ids[5], in: recents)
        #expect(recents.first == ids[5])
        #expect(recents.filter { $0 == ids[5] }.count == 1)
    }
}
