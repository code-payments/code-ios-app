//
//  RosterSearchTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
import FlipcashStore
import SQLite
@testable import Flipcash

@Suite("Roster sync and search")
@MainActor
struct RosterSearchTests {

    // MARK: - Full read -

    @Test("A first open pages until has_more is false and persists every member")
    func pagesToEnd() async throws {
        let harness = try Harness(pages: 3, perPage: 100)
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(harness.fetching.calls == 3)
        let state = try harness.state()
        #expect(state.heldCount == 300)
        #expect(state.fullySynced)
        #expect(state.truncated == false)
        #expect(state.watermark == 2)
        #expect(state.needsFullRead == false)
    }

    @Test("The page cap stops a read, and search uses what is held")
    func capStopsPaging() async throws {
        let harness = try Harness(pages: 5, perPage: 10, pageCap: 2)
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(harness.fetching.calls == 2)
        let state = try harness.state()
        #expect(state.heldCount == 20)
        #expect(state.truncated)
        #expect(state.needsFullRead == false)

        #expect(try await harness.search.search(chatID: harness.chatID, query: "member", limit: 100).count == 20)

        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(harness.fetching.calls == 2)
    }

    @Test("A synced group is not read again while the roster hasn't moved")
    func noReadWhenCurrent() async throws {
        let harness = try Harness(pages: 1, perPage: 5)
        await harness.sync.syncIfNeeded(harness.chatID)
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(harness.fetching.calls == 1)
    }

    @Test("A failed page records nothing")
    func failedPageRecordsNothing() async throws {
        let harness = try Harness(pages: 2, perPage: 5)
        harness.fetching.failingCalls = [2]
        await harness.sync.syncIfNeeded(harness.chatID)

        let state = try harness.state()
        #expect(state.heldCount == 0)
        #expect(state.fullySynced == false)
    }

    @Test("A read whose pages report different versions drops nothing and owes a reconcile")
    func midReadVersionChange() async throws {
        let harness = try Harness(members: [member("Ann"), member("Bea")], perPage: 1)
        await harness.sync.syncIfNeeded(harness.chatID)

        let departed = harness.fetching.members[1]
        harness.fetching.members = [harness.fetching.members[0], member("Cal")]
        harness.fetching.pageVersions = [3, 4]
        try harness.database.markRosterReconcilePending(harness.chatID)
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(try harness.heldIDs().contains(departed.userID!))
        #expect(try harness.state().reconcilePending)
    }

    // MARK: - Catch-up -

    @Test("Missed joins are recovered from the first page, stopping at the watermark")
    func catchUpRecoversJoins() async throws {
        let harness = try Harness(pages: 3, perPage: 100)
        await harness.sync.syncIfNeeded(harness.chatID)

        let missed = (0..<4).map { member("New \($0)", version: 5 + UInt64($0)) }
        let streamed = member("Streamed", version: 9)
        harness.fetching.members = [streamed] + missed.reversed() + harness.fetching.members
        harness.fetching.version = 9
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [joined(streamed, count: 305, version: 9)]))

        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(harness.fetching.calls == 4)
        let state = try harness.state()
        #expect(state.heldCount == 305)
        #expect(state.watermark == 9)
        #expect(state.needsCatchUp == false)
    }

    @Test("An equal count moves the watermark to the page's version, not the stream's")
    func equalCountUsesPageVersion() async throws {
        let ann = member("Ann")
        let max = member("Max")
        let harness = try Harness(members: [ann, max])
        await harness.sync.syncIfNeeded(harness.chatID)

        let yan = member("Yan", version: 10)
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 1, version: 9), change: .left(userID: max.userID!)),
            joined(yan, count: 2, version: 10),
        ]))

        // The page trails the stream: it is at version 8, before Max left and Yan joined.
        let wes = member("Wes", version: 8)
        harness.fetching.members = [wes, ann, max]
        harness.fetching.version = 8
        await harness.sync.syncIfNeeded(harness.chatID)

        let state = try harness.state()
        #expect(state.heldCount == 3)
        #expect(state.watermark == 8)
        #expect(try Set(harness.heldIDs()) == [ann.userID!, wes.userID!, yan.userID!])
    }

    @Test("More members held than counted owes a reconcile that survives a failed read")
    func unseenLeaveSetsPending() async throws {
        let cal = member("Cal")
        let harness = try Harness(members: [member("Ann"), member("Bea"), cal])
        await harness.sync.syncIfNeeded(harness.chatID)

        let yan = member("Yan", version: 4)
        harness.fetching.members = [yan] + harness.fetching.members.filter { $0.userID != cal.userID }
        harness.fetching.version = 4
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [joined(yan, count: 3, version: 4)]))

        harness.fetching.failingCalls = [3]
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(try harness.state().reconcilePending)
        #expect(try harness.heldIDs().contains(cal.userID!))

        harness.fetching.failingCalls = []
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(try harness.state().reconcilePending == false)
        #expect(try harness.heldIDs().contains(cal.userID!) == false)
    }

    @Test("An unseen leave runs one reconcile even when triggered twice")
    func reconcileRunsOnce() async throws {
        let cal = member("Cal")
        let harness = try Harness(members: [member("Ann"), member("Bea"), cal])
        await harness.sync.syncIfNeeded(harness.chatID)

        let yan = member("Yan", version: 4)
        harness.fetching.members = [yan] + harness.fetching.members.filter { $0.userID != cal.userID }
        harness.fetching.version = 4
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [joined(yan, count: 3, version: 4)]))

        async let first: Void = harness.sync.syncIfNeeded(harness.chatID)
        async let second: Void = harness.sync.syncIfNeeded(harness.chatID)
        _ = await (first, second)

        // One for the initial read, one for the catch-up, one for the reconcile.
        #expect(harness.fetching.calls == 3)
        #expect(try harness.heldIDs().contains(cal.userID!) == false)
    }

    @Test("A reconcile drops departed members but keeps one the stream added after the page")
    func reconcileKeepsNewerMembers() async throws {
        let cal = member("Cal")
        let harness = try Harness(members: [member("Ann"), member("Bea"), cal])
        await harness.sync.syncIfNeeded(harness.chatID)

        let zed = member("Zed", version: 6)
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [joined(zed, count: 3, version: 6)]))

        // Cal left at version 3, unseen; the pages are at version 4, before Zed joined.
        harness.fetching.members = harness.fetching.members.filter { $0.userID != cal.userID }
        harness.fetching.version = 4
        await harness.sync.syncIfNeeded(harness.chatID)

        let held = try harness.heldIDs()
        #expect(held.contains(cal.userID!) == false)
        #expect(held.contains(zed.userID!))
        #expect(try harness.state().reconcilePending == false)
    }

    // MARK: - Stream -

    @Test("A stream join adds the member to the index and a leave removes them")
    func streamJoinAndLeave() async throws {
        let harness = try Harness(pages: 1, perPage: 2)
        await harness.sync.syncIfNeeded(harness.chatID)

        let zed = member("Zed Quill", version: 3)
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [joined(zed, count: 3, version: 3)]))
        #expect(try await harness.search.search(chatID: harness.chatID, query: "qui").map(\.id) == [zed.userID!])

        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 2, version: 4), change: .left(userID: zed.userID!)),
        ]))
        #expect(try await harness.search.search(chatID: harness.chatID, query: "qui").isEmpty)
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

        #expect(try harness.heldIDs().contains(departed.userID!) == false)
    }

    @Test("A stale leave, older than the held join, changes nothing")
    func staleLeaveIgnored() async throws {
        let harness = try Harness(pages: 1, perPage: 2)
        await harness.sync.syncIfNeeded(harness.chatID)

        let zed = member("Zed Quill", version: 5)
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [joined(zed, count: 3, version: 5)]))
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 2, version: 3), change: .left(userID: zed.userID!)),
        ]))

        #expect(try await harness.search.search(chatID: harness.chatID, query: "qui").map(\.id) == [zed.userID!])
        #expect(try harness.state().heldCount == 3)
    }

    @Test("A profile write after a leave doesn't bring the member back")
    func profileAfterLeaveStaysOut() async throws {
        let harness = try Harness(pages: 1, perPage: 2)
        await harness.sync.syncIfNeeded(harness.chatID)
        let departed = harness.fetching.members[0]
        await harness.sync.apply(.rosterChanged(conversationID: harness.chatID, updates: [
            DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: 1, version: 3), change: .left(userID: departed.userID!)),
        ]))

        try harness.database.upsertUserProfile(
            Profile(displayName: "Zed Quill", phone: Phone?.none, email: nil, username: Username("zedq")),
            userID: departed.userID!
        )

        #expect(try await harness.search.search(chatID: harness.chatID, query: "qui").isEmpty)
        #expect(try await harness.search.search(chatID: harness.chatID, query: "zedq").isEmpty)
        #expect(try harness.state().heldCount == 1)
        #expect(try harness.heldIDs().contains(departed.userID!) == false)
    }

    // MARK: - Profiles -

    @Test("Opening the picker re-reads the first page and re-tokenizes a rename")
    func refreshRenames() async throws {
        let original = member("Old Name")
        let harness = try Harness(members: [original])
        await harness.sync.syncIfNeeded(harness.chatID)

        harness.fetching.members = [ConversationMember(userID: original.userID, displayName: "New Name", version: original.version)]
        await harness.search.prepare(chatID: harness.chatID)

        #expect(try await harness.names("new") == ["New Name"])
        #expect(try await harness.names("old") == [])
    }

    @Test("A cached profile re-tokenizes the user in every group")
    func profileRetokenizesEveryChat() async throws {
        let shared = member("Old Name")
        let harness = try Harness(members: [shared])
        let otherChat = ConversationID(data: Data(repeating: 0x08, count: 32))
        await harness.sync.syncIfNeeded(harness.chatID)
        await harness.sync.syncIfNeeded(otherChat)

        try harness.database.upsertUserProfile(
            Profile(displayName: "Nadia Renamed", phone: Phone?.none, email: nil, username: Username("nadia")),
            userID: shared.userID!
        )

        for chat in [harness.chatID, otherChat] {
            #expect(try await harness.search.search(chatID: chat, query: "ren").map(\.member.displayName) == ["Nadia Renamed"])
            #expect(try await harness.search.search(chatID: chat, query: "nadia").count == 1)
            #expect(try await harness.search.search(chatID: chat, query: "old").isEmpty)
        }
    }

    // MARK: - Matching -

    @Test("A prefix matches any word of the display name, and the username")
    func prefixMatching() async throws {
        let harness = try Harness(members: [
            member("Ana María Lopez", username: "anita"),
            member("Bob Stone", username: "rocky"),
            member("María García"),
            member("Luis García"),
        ])
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(try await harness.names("ana") == ["Ana María Lopez"])
        #expect(try await harness.names("lop") == ["Ana María Lopez"])
        #expect(try await harness.names("roc") == ["Bob Stone"])
        #expect(try await harness.names("＠roc") == ["Bob Stone"])
        #expect(try await harness.names("ana lo") == ["Ana María Lopez"])
        #expect(try await harness.names("ma garc") == ["María García"])
        #expect(try await harness.names("tone") == [])
    }

    @Test("Matching ignores case and diacritics")
    func caseAndDiacritics() async throws {
        let harness = try Harness(members: [member("Érica Souza"), member("ERIK")])
        await harness.sync.syncIfNeeded(harness.chatID)

        #expect(try await harness.names("eri") == ["Érica Souza", "ERIK"])
        #expect(try await harness.names("ÉRI").count == 2)
        #expect(try await harness.names("souz") == ["Érica Souza"])
    }

    @Test("An emoji right after the prefix still matches")
    func astralCharacterAfterPrefix() async throws {
        let harness = try Harness(members: [member("Bob🔥")])
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(try await harness.names("bob") == ["Bob🔥"])
    }

    // MARK: - Ranking -

    @Test("A recent speaker outranks an exact username, which outranks the rest by name")
    func ranking() async throws {
        let speaker = member("Sam Zulu", username: "samz")
        let exact = member("Yara Sam", username: "sam")
        let alphaA = member("Samantha Adams")
        let alphaB = member("Samuel Brown")
        let harness = try Harness(members: [alphaB, exact, alphaA, speaker])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: speaker.userID!)

        #expect(try await harness.names("sam") == ["Sam Zulu", "Yara Sam", "Samantha Adams", "Samuel Brown"])
    }

    @Test("The most recent speaker ranks above an earlier one")
    func recencyOrder() async throws {
        let first = member("Ann One")
        let second = member("Ann Two")
        let harness = try Harness(members: [first, second])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: first.userID!)
        try harness.postMessage(from: second.userID!)

        #expect(try await harness.names("ann") == ["Ann Two", "Ann One"])
    }

    @Test("Only the newest 50 messages count toward recent speakers")
    func recencyWindow() async throws {
        let old = member("Ann Old")
        let chatty = member("Zed Chatty")
        let harness = try Harness(members: [old, chatty])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: old.userID!)
        for _ in 0..<50 { try harness.postMessage(from: chatty.userID!) }

        #expect(try await harness.names("") == ["Zed Chatty"])
    }

    @Test("Folded name ties fall back to the raw display name")
    func rawNameTiebreak() async throws {
        let harness = try Harness(members: [member("éva"), member("Eva")])
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(try await harness.names("eva") == ["Eva", "éva"])
    }

    @Test("Names sort by code point, so U+FFFD comes before an emoji")
    func codePointOrder() async throws {
        // UTF-16 order would put the emoji's surrogate (D83D) first; neither character decomposes.
        let harness = try Harness(members: [member("Ann \u{1F600}"), member("Ann \u{FFFD}")])
        await harness.sync.syncIfNeeded(harness.chatID)
        #expect(try await harness.names("ann") == ["Ann \u{FFFD}", "Ann \u{1F600}"])
    }

    @Test("An empty query returns recent speakers only")
    func emptyQuery() async throws {
        let speaker = member("Talker")
        let harness = try Harness(members: [speaker, member("Quiet")])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: speaker.userID!)

        #expect(try await harness.names("") == ["Talker"])
        #expect(try await harness.names("＠") == ["Talker"])
    }

    @Test("The signed-in user is never a match, even after speaking")
    func excludesSelf() async throws {
        let me = member("Sam Me", username: "me")
        let harness = try Harness(members: [me, member("Sam Other")], selfUserID: me.userID!)
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: me.userID!)

        #expect(try await harness.names("sam") == ["Sam Other"])
        #expect(try await harness.names("") == [])
    }

    @Test("A blocked user is never a match")
    func excludesBlocked() async throws {
        let blocked = member("Sam Blocked")
        let harness = try Harness(members: [blocked, member("Sam Other")], blocked: [blocked.userID!])
        await harness.sync.syncIfNeeded(harness.chatID)
        try harness.postMessage(from: blocked.userID!)

        #expect(try await harness.names("sam") == ["Sam Other"])
    }
}

// MARK: - Support -

private func member(_ displayName: String, username: String? = nil, version: UInt64 = 1) -> ConversationMember {
    ConversationMember(userID: UUID(), displayName: displayName, username: username.flatMap(Username.init), version: version)
}

private func joined(_ member: ConversationMember, count: UInt64, version: UInt64) -> DecodedRosterUpdate {
    DecodedRosterUpdate(rosterSummary: ConversationRosterSummary(memberCount: count, version: version), change: .joined(member: member, chat: nil))
}

@MainActor
private struct Harness {
    let database: Database
    let fetching: FakeRosterFetching
    let sync: RosterSync
    let search: LocalRosterSearch
    let chatID = ConversationID(data: Data(repeating: 0x07, count: 32))
    private let messageCounter = Counter()

    init(members: [ConversationMember], perPage: Int = 100, pageCap: Int = RosterSync.defaultPageCap, selfUserID: UserID = UUID(), blocked: Set<UserID> = []) throws {
        let (database, _) = try Database.makeTemp()
        self.database = database
        self.fetching = FakeRosterFetching(members: members, perPage: perPage)
        self.sync = RosterSync(fetching: fetching, database: database, owner: .generate()!, pageCap: pageCap)
        self.search = LocalRosterSearch(database: database, roster: sync, selfUserID: selfUserID, blockedUserIDs: { blocked })
    }

    init(pages: Int, perPage: Int, pageCap: Int = RosterSync.defaultPageCap) throws {
        let members = (0..<(pages * perPage)).map { ConversationMember(userID: UUID(), displayName: "Member \($0)", version: 1) }
        try self.init(members: members, perPage: perPage, pageCap: pageCap)
    }

    func state() throws -> RosterSyncState {
        try #require(try database.rosterSyncState(conversationID: chatID))
    }

    func heldIDs() throws -> [UserID] {
        try database.rosterEntries(conversationID: chatID).compactMap(\.member.userID)
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

private extension Database {
    /// Stands in for a catch-up that found more members held than counted.
    func markRosterReconcilePending(_ conversationID: ConversationID) throws {
        let s = RosterSyncTable()
        try writer.run(s.table.filter(s.conversationId == conversationID.data).update(s.reconcilePending <- true))
    }
}

nonisolated private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func next() -> UInt64 { lock.withLock { value += 1; return value } }
}

/// Serves a roster in pages, most recently joined first, like `Chat.GetRoster`.
nonisolated private final class FakeRosterFetching: RosterFetching, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private let perPage: Int
    private var _members: [ConversationMember]
    private var _version: UInt64 = 2
    private var _pageVersions: [UInt64]?
    private var _failingCalls: Set<Int> = []
    private var _calls = 0

    init(members: [ConversationMember], perPage: Int) {
        self._members = members
        self.perPage = perPage
    }

    var members: [ConversationMember] {
        get { lock.withLock { _members } }
        set { lock.withLock { _members = newValue } }
    }

    /// The roster version every page reports, unless ``pageVersions`` overrides it per page.
    var version: UInt64 {
        get { lock.withLock { _version } }
        set { lock.withLock { _version = newValue } }
    }

    var pageVersions: [UInt64]? {
        get { lock.withLock { _pageVersions } }
        set { lock.withLock { _pageVersions = newValue } }
    }

    /// 1-based call numbers that throw instead of returning a page.
    var failingCalls: Set<Int> {
        get { lock.withLock { _failingCalls } }
        set { lock.withLock { _failingCalls = newValue } }
    }

    var calls: Int { lock.withLock { _calls } }

    func getRosterPage(owner: KeyPair, conversationID: ConversationID, pagingToken: Data?) async throws -> FlipClient.RosterPage {
        try lock.withLock {
            _calls += 1
            if _failingCalls.contains(_calls) { throw Failure() }
            let start = pagingToken.map { Int(String(decoding: $0, as: UTF8.self))! } ?? 0
            let end = min(start + perPage, _members.count)
            let next = end < _members.count ? Data(String(end).utf8) : nil
            let pageIndex = start / perPage
            let version = _pageVersions.flatMap { pageIndex < $0.count ? $0[pageIndex] : nil } ?? _version
            return FlipClient.RosterPage(
                members: Array(_members[start..<end]),
                rosterSummary: ConversationRosterSummary(memberCount: UInt64(_members.count), version: version),
                nextPagingToken: next
            )
        }
    }
}
