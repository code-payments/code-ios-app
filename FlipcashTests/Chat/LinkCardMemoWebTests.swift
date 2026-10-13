//
//  LinkCardMemoWebTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// Web answers persist across memos over one store, under the TTLs in parity decision D8.
@MainActor
@Suite("LinkCardMemo web persistence")
struct LinkCardMemoWebTests {

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private static let key = "web:https://example.com/a"
    private static let page = LinkCard.Web.Resolved(title: "Title", description: "About", imageURL: URL(string: "https://example.com/i.png"), host: "example.com")

    /// Waits for `memo`'s write-through to land in `database`.
    private func waitForRow(_ key: String, in database: Database) async throws {
        try await waitUntil { (try? database.linkPreviews(since: .distantPast))?.contains { $0.key == key } == true }
    }

    /// A store whose load never returns until the test releases it.
    private final class StuckStore: LinkPreviewStoring, @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        func linkPreviews(since: Date) throws -> [LinkPreviewRow] { release.wait(); return [] }
        func upsertLinkPreview(key: String, json: Data, updatedAt: Date) throws {}
        func deleteLinkPreviews(before: Date) throws {}
    }

    @Test func aChatWaitsAtMost300MsForTheSavedRows() async {
        let store = StuckStore()
        defer { store.release.signal() }
        let memo = LinkCardMemo(store: store)
        #expect(!memo.isLoaded)
        let start = ContinuousClock.now
        await memo.awaitLoaded()
        let waited = ContinuousClock.now - start
        #expect(waited >= .milliseconds(290))
        #expect(waited < .milliseconds(1000))
        #expect(!memo.isLoaded)
    }

    @Test func aMemoWithNoStoreIsLoadedFromTheStart() {
        #expect(LinkCardMemo().isLoaded)
    }

    @Test func aRecordedAnswerSurvivesANewMemoOverTheSameStore() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }

        LinkCardMemo(store: database).recordWeb(.resolved(Self.page), for: Self.key)
        try await waitForRow(Self.key, in: database)

        let reopened = LinkCardMemo(store: database)
        await reopened.awaitLoaded()
        #expect(reopened.web(Self.key) == .resolved(Self.page))
    }

    @Test func aStoredNoneRowOlderThanItsTTLReadsAsNil() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let clock = Clock(Date())
        try database.upsertLinkPreview(key: Self.key, json: StoredWeb(.none).encoded,
                                       updatedAt: clock.now.addingTimeInterval(-WebLinks.emptyTTL - 60))

        let memo = LinkCardMemo(store: database, now: { clock.now })
        await memo.awaitLoaded()
        #expect(memo.web(Self.key) == nil)
    }

    @Test func aLoadDeletesRowsOlderThanTheResolvedTTL() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let now = Date()
        try database.upsertLinkPreview(key: "web:https://old.example/", json: StoredWeb(.resolved(Self.page)).encoded,
                                       updatedAt: now.addingTimeInterval(-WebLinks.resolvedTTL - 60))
        try database.upsertLinkPreview(key: Self.key, json: StoredWeb(.resolved(Self.page)).encoded, updatedAt: now)

        let memo = LinkCardMemo(store: database, now: { now })
        await memo.awaitLoaded()
        #expect(try database.linkPreviews(since: .distantPast).map(\.key) == [Self.key])
    }

    @Test func theStoredShapeMatchesAndroid() throws {
        let none = try #require(JSONSerialization.jsonObject(with: StoredWeb(.none).encoded) as? [String: Any])
        #expect(Set(none.keys) == ["title", "description", "imageUrl", "host"], "all four keys, nulls included")
        #expect(none.values.allSatisfy { $0 is NSNull }, "a null title is how a None answer is stored")
        let decoded = try #require(StoredWeb.decode(Data(#"{"title":"T","description":null,"imageUrl":"https://e.com/i","host":"e.com"}"#.utf8)))
        #expect(decoded.state == .resolved(.init(title: "T", description: nil, imageURL: URL(string: "https://e.com/i"), host: "e.com")))
    }

    @Test func anAnswerExactlyAtItsTTLStillReads() {
        let clock = Clock(Date(timeIntervalSince1970: 0))
        let memo = LinkCardMemo(now: { clock.now })
        memo.recordWeb(.none, for: Self.key)
        clock.now = Date(timeIntervalSince1970: WebLinks.emptyTTL)
        #expect(memo.web(Self.key) == LinkCard.Web.State.none)
        clock.now = Date(timeIntervalSince1970: WebLinks.emptyTTL + 0.001)
        #expect(memo.web(Self.key) == nil)
    }
}
