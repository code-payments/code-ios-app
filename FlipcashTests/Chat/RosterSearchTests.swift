//
//  RosterSearchTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
@testable import Flipcash

@Suite("Roster sync and search")
@MainActor
struct RosterSearchTests {

    // MARK: - Paging -

    @Test("A sync pages until has_more is false and persists every member")
    func pagesToEnd() async throws {
        let harness = try Harness(pages: 3, perPage: 100)
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(harness.fetching.calls == 3)
        let state = try #require(try harness.database.rosterSyncState(conversationID: harness.chatID))
        #expect(state.heldCount == 300)
        #expect(state.isCapped == false)
        #expect(state.needsFullSync == false)
    }

    @Test("The page cap stops a sync and search uses what is held")
    func capStopsPaging() async throws {
        let harness = try Harness(pages: 5, perPage: 10, pageCap: 2)
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(harness.fetching.calls == 2)
        let state = try #require(try harness.database.rosterSyncState(conversationID: harness.chatID))
        #expect(state.heldCount == 20)
        #expect(state.isCapped)
        #expect(state.needsFullSync == false)

        let matches = try await harness.search.search(chatID: harness.chatID, query: "member", limit: 100)
        #expect(matches.count == 20)
    }

    @Test("A synced group is not paged again on the next open")
    func noResyncWhenComplete() async throws {
        let harness = try Harness(pages: 1, perPage: 5)
        await harness.sync.syncIfNeeded(harness.chatID)
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(harness.fetching.calls == 1)
    }

    // MARK: - Stream -

    @Test("A stream join adds the member to the index and a leave removes them")
    func streamJoinAndLeave() async throws {
        let harness = try Harness(pages: 1, perPage: 2)
        await harness.sync.syncIfNeeded(harness.chatID)

        let zed = UUID()
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(
                rosterSummary: ConversationRosterSummary(memberCount: 3, version: 3),
                change: .joined(member: ConversationMember(userID: zed, displayName: "Zed Quill", version: 3), chat: nil)
            ),
        ]))
        #expect(try await harness.search.search(chatID: harness.chatID, query: "qui", limit: 10).map(\.id) == [zed])

        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 2, version: 4), change: .left(userID: zed)),
        ]))
        #expect(try await harness.search.search(chatID: harness.chatID, query: "qui", limit: 10).isEmpty)
    }

    @Test("A page trailing the stream cannot bring back a member who left")
    func trailingPageDoesNotResurrect() async throws {
        let harness = try Harness(pages: 1, perPage: 2)
        try harness.database.beginTrackingRoster(conversationID: harness.chatID)
        let departed = harness.fetching.members[0]
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 1, version: 3), change: .left(userID: departed.userID!)),
        ]))
        await harness.sync.syncIfNeeded(harness.chatID)

        let held = try harness.database.rosterEntries(conversationID: harness.chatID).compactMap(\.member.userID)
        #expect(!held.contains(departed.userID!))
    }

    @Test("A skipped stream version marks the group for re-sync")
    func versionGapMarksResync() async throws {
        let harness = try Harness(pages: 1, perPage: 2)
        await harness.sync.syncIfNeeded(harness.chatID)

        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(
                rosterSummary: ConversationRosterSummary(memberCount: 3, version: 9),
                change: .joined(member: ConversationMember(userID: UUID(), displayName: "Late", version: 9), chat: nil)
            ),
        ]))
        #expect(try harness.database.rosterSyncState(conversationID: harness.chatID)?.needsFullSync == true)
    }

    // MARK: - Matching -

    @Test("A prefix matches any word of the display name, and the username")
    func prefixMatching() async throws {
        let harness = try Harness(members: [
            member("Ana María Lopez", username: "anita"),
            member("Bob Stone", username: "rocky"),
        ])
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(try await harness.names("ana") == ["Ana María Lopez"])
        #expect(try await harness.names("mar") == ["Ana María Lopez"])
        #expect(try await harness.names("lop") == ["Ana María Lopez"])
        #expect(try await harness.names("roc") == ["Bob Stone"])
        #expect(try await harness.names("@roc") == ["Bob Stone"])
        #expect(try await harness.names("ana lo") == ["Ana María Lopez"])
        #expect(try await harness.names("tone") == [])
    }

    @Test("Matching ignores case and diacritics")
    func caseAndDiacritics() async throws {
        let harness = try Harness(members: [member("Érica Souza", username: nil), member("ERIK", username: nil)])
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(try await harness.names("eri") == ["ERIK", "Érica Souza"].sorted { RosterSearchText.normalize($0) < RosterSearchText.normalize($1) })
        #expect(try await harness.names("ÉRI").count == 2)
        #expect(try await harness.names("souz") == ["Érica Souza"])
    }

    // MARK: - Ranking -

    @Test("Recent speakers rank first, then an exact username, then by display name")
    func ranking() async throws {
        let speaker = member("Sam Zulu", username: "samz")
        let exact = member("Yara Sam", username: "sam")
        let alphaA = member("Samantha Adams", username: nil)
        let alphaB = member("Samuel Brown", username: nil)
        let harness = try Harness(members: [alphaB, exact, alphaA, speaker])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: speaker.userID!)

        #expect(try await harness.names("sam") == ["Sam Zulu", "Yara Sam", "Samantha Adams", "Samuel Brown"])
    }

    @Test("The most recent speaker ranks above an earlier one")
    func recencyOrder() async throws {
        let first = member("Ann One", username: nil)
        let second = member("Ann Two", username: nil)
        let harness = try Harness(members: [first, second])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: first.userID!)
        try harness.postMessage(from: second.userID!)

        #expect(try await harness.names("ann") == ["Ann Two", "Ann One"])
    }

    @Test("An empty query returns recent speakers only")
    func emptyQuery() async throws {
        let speaker = member("Talker", username: nil)
        let harness = try Harness(members: [speaker, member("Quiet", username: nil)])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: speaker.userID!)

        #expect(try await harness.names("") == ["Talker"])
        #expect(try await harness.names("@") == ["Talker"])
    }

    @Test("The signed-in user is never a match, even after speaking")
    func excludesSelf() async throws {
        let me = member("Sam Me", username: "me")
        let harness = try Harness(members: [me, member("Sam Other", username: nil)], selfUserID: me.userID!)
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: me.userID!)

        #expect(try await harness.names("sam") == ["Sam Other"])
        #expect(try await harness.names("") == [])
    }

    @Test("A first-page refresh rewrites a renamed member's tokens")
    func refreshRenames() async throws {
        let original = member("Old Name", username: nil)
        let harness = try Harness(members: [original])
        await harness.sync.syncIfNeeded(harness.chatID)

        harness.fetching.members = [ConversationMember(userID: original.userID, displayName: "New Name", version: original.version)]
        await harness.search.prepare(chatID: harness.chatID)

        #expect(try await harness.names("new") == ["New Name"])
        #expect(try await harness.names("old") == [])
    }
}

// MARK: - Support -

private func member(_ displayName: String, username: String?, version: UInt64 = 1) -> ConversationMember {
    ConversationMember(userID: UUID(), displayName: displayName, username: username.flatMap(Username.init), version: version)
}

@MainActor
private struct Harness {
    let database: Database
    let fetching: FakeRosterFetching
    let sync: RosterSync
    let search: LocalRosterSearch
    let chatID = ConversationID(data: Data(repeating: 0x07, count: 32))
    private let url: URL
    private let messageCounter = Counter()

    init(members: [ConversationMember], perPage: Int = 100, pageCap: Int = RosterSync.defaultPageCap, selfUserID: UserID = UUID()) throws {
        let (database, url) = try Database.makeTemp()
        self.database = database
        self.url = url
        self.fetching = FakeRosterFetching(members: members, perPage: perPage)
        self.sync = RosterSync(fetching: fetching, database: database, owner: .generate()!, pageCap: pageCap)
        self.search = LocalRosterSearch(database: database, roster: sync, selfUserID: selfUserID)
    }

    init(pages: Int, perPage: Int, pageCap: Int = RosterSync.defaultPageCap) throws {
        let members = (0..<(pages * perPage)).map { ConversationMember(userID: UUID(), displayName: "Member \($0)", version: 1) }
        try self.init(members: members, perPage: perPage, pageCap: pageCap)
    }

    func names(_ query: String) async throws -> [String] {
        try await search.search(chatID: chatID, query: query, limit: 10).map(\.member.displayName)
    }

    func postMessage(from sender: UserID) throws {
        let id = messageCounter.next()
        try database.upsertConversationMessages([
            ConversationMessage(id: MessageID(value: id), senderID: sender, content: .text("hi"), date: .now, unreadSeq: id),
        ], conversationID: chatID)
    }
}

nonisolated private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func next() -> UInt64 { lock.withLock { value += 1; return value } }
}

/// Serves a fixed roster in pages, most recent first, like `Chat.GetRoster`.
nonisolated private final class FakeRosterFetching: RosterFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let perPage: Int
    private var _members: [ConversationMember]
    private var _calls = 0

    init(members: [ConversationMember], perPage: Int) {
        self._members = members
        self.perPage = perPage
    }

    var members: [ConversationMember] {
        get { lock.withLock { _members } }
        set { lock.withLock { _members = newValue } }
    }

    var calls: Int { lock.withLock { _calls } }

    func getRosterPage(owner: KeyPair, conversationID: ConversationID, pagingToken: Data?) async throws -> FlipClient.RosterPage {
        lock.withLock {
            _calls += 1
            let start = pagingToken.map { Int(String(decoding: $0, as: UTF8.self))! } ?? 0
            let end = min(start + perPage, _members.count)
            let next = end < _members.count ? Data(String(end).utf8) : nil
            return FlipClient.RosterPage(
                members: Array(_members[start..<end]),
                rosterSummary: ConversationRosterSummary(memberCount: UInt64(_members.count), version: 2),
                nextPagingToken: next
            )
        }
    }
}
