//
//  ServerMentionSearchTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Server mention search")
struct ServerMentionSearchTests {

    private let chatID = ConversationID.test(0x0A)
    private let zoe = suggestion("Zoe Adams", "zoe", lastSentAt: 300)
    private let bob = suggestion("Bob Stone", "bob", lastSentAt: 200)
    private let alice = suggestion("Alice Park", "alice", lastSentAt: nil)

    private func makeSearch(
        pool: [MentionSuggestion] = [],
        error: (any Error)? = nil,
        blocked: Set<UserID> = []
    ) -> (ServerMentionSearch, FakeFetching) {
        let fetching = FakeFetching(pool: pool, error: error)
        let search = ServerMentionSearch(
            fetching: fetching,
            owner: .generate()!,
            blockedUserIDs: { blocked }
        )
        return (search, fetching)
    }

    private func names(_ matches: [MemberMatch]) -> [String] {
        matches.map(\.member.displayName)
    }

    @Test("Matches keep the server's order rather than sorting")
    func keepsServerOrder() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob, alice])
        await search.prepare(chatID: chatID)

        let matches = try await search.search(chatID: chatID, query: "a", limit: 20)

        #expect(names(matches) == ["Zoe Adams", "Alice Park"])
    }

    @Test("Every query word must prefix a name word or the username")
    func matchesEveryWord() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob, alice])
        await search.prepare(chatID: chatID)

        #expect(names(try await search.search(chatID: chatID, query: "bob st", limit: 20)) == ["Bob Stone"])
        #expect(names(try await search.search(chatID: chatID, query: "ali", limit: 20)) == ["Alice Park"])
        #expect(try await search.search(chatID: chatID, query: "zoe park", limit: 20).isEmpty)
    }

    @Test("A bare @ shows the head of the pool")
    func bareAtShowsHead() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob, alice])
        await search.prepare(chatID: chatID)

        let matches = try await search.search(chatID: chatID, query: "", limit: 2)

        #expect(names(matches) == ["Zoe Adams", "Bob Stone"])
    }

    @Test("A blocked user is never offered")
    func dropsBlocked() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob, alice], blocked: [bob.userID])
        await search.prepare(chatID: chatID)

        #expect(names(try await search.search(chatID: chatID, query: "", limit: 20)) == ["Zoe Adams", "Alice Park"])
    }

    @Test("The pool is fetched once per composing session")
    func fetchesOncePerSession() async throws {
        let (search, fetching) = makeSearch(pool: [zoe, bob])

        #expect(await search.prepare(chatID: chatID))
        _ = try await search.search(chatID: chatID, query: "z", limit: 20)
        _ = try await search.search(chatID: chatID, query: "zo", limit: 20)
        #expect(fetching.calls == 1)

        await search.prepare(chatID: chatID)
        #expect(fetching.calls == 2)
    }

    @Test("A search before prepare fetches the pool, and prepare joins that fetch")
    func searchBeforePrepare() async throws {
        let (search, fetching) = makeSearch(pool: [zoe, bob])

        #expect(names(try await search.search(chatID: chatID, query: "", limit: 20)) == ["Zoe Adams", "Bob Stone"])
        #expect(fetching.calls == 1)
    }

    @Test("A new message moves its sender to the front")
    func movesSenderToFront() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob, alice])
        await search.prepare(chatID: chatID)

        search.apply(.sent([message(from: alice.userID, at: 400)], in: chatID))

        #expect(names(try await search.search(chatID: chatID, query: "", limit: 20)) == ["Alice Park", "Zoe Adams", "Bob Stone"])
    }

    @Test("A message no newer than the sender's last send leaves the order alone")
    func ignoresOlderMessage() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob, alice])
        await search.prepare(chatID: chatID)

        search.apply(.sent([message(from: bob.userID, at: 200)], in: chatID))

        #expect(names(try await search.search(chatID: chatID, query: "", limit: 20)) == ["Zoe Adams", "Bob Stone", "Alice Park"])
    }

    @Test("A sender outside the pool is not added")
    func ignoresUnknownSender() async throws {
        let (search, _) = makeSearch(pool: [zoe, bob])
        await search.prepare(chatID: chatID)

        search.apply(.sent([message(from: UUID(), at: 500)], in: chatID))
        search.apply(.sent([message(from: bob.userID, at: 500)], in: .test(0x0B)))

        #expect(names(try await search.search(chatID: chatID, query: "", limit: 20)) == ["Zoe Adams", "Bob Stone"])
    }

    @Test(
        "A failed fetch matches nobody and reports the prepare as failed",
        arguments: [ErrorGetMentionSuggestions.denied, .notFound, .transportFailure]
    )
    func failedFetchIsEmpty(error: ErrorGetMentionSuggestions) async throws {
        let (search, _) = makeSearch(error: error)

        #expect(await search.prepare(chatID: chatID) == false)
        #expect(try await search.search(chatID: chatID, query: "", limit: 20).isEmpty)
        #expect(try await search.search(chatID: chatID, query: "al", limit: 20).isEmpty)
    }

    @Test("The next prepare fetches again after a failure")
    func retriesAfterFailure() async throws {
        let (search, fetching) = makeSearch(error: ErrorGetMentionSuggestions.transportFailure)
        #expect(await search.prepare(chatID: chatID) == false)
        fetching.error = nil
        fetching.pool = [zoe]

        #expect(await search.prepare(chatID: chatID))
        #expect(names(try await search.search(chatID: chatID, query: "", limit: 20)) == ["Zoe Adams"])
    }

    // MARK: - Fakes

    final class FakeFetching: MentionSuggestionFetching, @unchecked Sendable {
        var pool: [MentionSuggestion]
        var error: (any Error)?
        private(set) var calls = 0

        init(pool: [MentionSuggestion], error: (any Error)?) {
            self.pool = pool
            self.error = error
        }

        func getMentionSuggestions(owner: KeyPair, conversationID: ConversationID) async throws -> [MentionSuggestion] {
            calls += 1
            if let error { throw error }
            return pool
        }
    }
}

private func suggestion(_ displayName: String, _ username: String, lastSentAt: TimeInterval?) -> MentionSuggestion {
    let userID = UUID()
    return MentionSuggestion(
        userID: userID,
        profile: Profile(
            displayName: displayName,
            phone: Phone?.none,
            email: nil,
            userID: userID,
            username: Username(username)
        ),
        lastSentAt: lastSentAt.map { Date(timeIntervalSince1970: $0) }
    )
}

private func message(from senderID: UserID, at time: TimeInterval) -> ConversationMessage {
    ConversationMessage(
        id: MessageID(value: UInt64(time)),
        senderID: senderID,
        content: .text("hi"),
        date: Date(timeIntervalSince1970: time),
        unreadSeq: 0
    )
}
