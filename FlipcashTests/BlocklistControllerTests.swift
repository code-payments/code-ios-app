//
//  BlocklistControllerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@Suite("BlocklistController")
@MainActor
struct BlocklistControllerTests {

    /// A fake blocklist backend capturing calls and returning canned pages.
    final class FakeBlocklisting: BlocklistFetching {
        var page: [BlockedUserProfile] = []
        var blocked: [UserID] = []
        var unblocked: [UserID] = []
        /// When set, `getBlockedUserProfiles()` throws this instead of returning `page`.
        var error: Error?
        /// How many times the list has been pulled from the backend.
        private(set) var calls = 0

        /// When true, each pull parks until ``open()``. The latch stays open afterwards so
        /// a pull that arrives late resumes rather than hanging the test.
        var gated = false
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            let resuming = waiting
            waiting = []
            resuming.forEach { $0.resume() }
        }

        func getBlockedUserProfiles() async throws -> [BlockedUserProfile] {
            calls += 1
            if gated, !isOpen {
                await withCheckedContinuation { waiting.append($0) }
            }
            if let error { throw error }
            return page
        }
        func block(userID: UserID) async throws { blocked.append(userID) }
        func unblock(userID: UserID) async throws { unblocked.append(userID) }
    }

    private func makeController(_ fake: FakeBlocklisting) -> BlocklistController {
        BlocklistController(fetching: fake, database: .mock)
    }

    @Test("refresh loads the blocklist into memory + cache")
    func refreshPopulates() async {
        let fake = FakeBlocklisting()
        let id = UUID()
        fake.page = [BlockedUserProfile(userID: id, blockedAt: .init(timeIntervalSince1970: 1), displayName: "Fred", avatarBlurhash: nil)]
        let controller = makeController(fake)
        await controller.refresh()
        #expect(controller.blockedUsers.map(\.userID) == [id])
        #expect(controller.isBlocked(id))
    }

    @Test("block calls the backend and inserts optimistically")
    func blockOptimistic() async throws {
        let fake = FakeBlocklisting()
        let controller = makeController(fake)
        let id = UUID()
        try await controller.block(userID: id, displayName: "Fred", avatarBlurhash: "L6")
        #expect(fake.blocked == [id])
        #expect(controller.isBlocked(id))
    }

    @Test("unblock calls the backend and removes optimistically")
    func unblockOptimistic() async throws {
        let fake = FakeBlocklisting()
        let id = UUID()
        fake.page = [BlockedUserProfile(userID: id, blockedAt: .init(timeIntervalSince1970: 1), displayName: "Fred", avatarBlurhash: nil)]
        let controller = makeController(fake)
        await controller.refresh()
        try await controller.unblock(userID: id)
        #expect(fake.unblocked == [id])
        #expect(!controller.isBlocked(id))
    }

    @Test("refresh failure keeps the existing list")
    func refreshFailureKeepsExistingList() async {
        let fake = FakeBlocklisting()
        let id = UUID()
        fake.page = [BlockedUserProfile(userID: id, blockedAt: .init(timeIntervalSince1970: 1), displayName: "Fred", avatarBlurhash: nil)]
        let controller = makeController(fake)
        await controller.refresh()
        #expect(controller.isBlocked(id))

        // Make the next refresh fail — the existing list must survive unchanged.
        fake.error = URLError(.notConnectedToInternet)
        await controller.refresh()
        #expect(controller.blockedUsers.map(\.userID) == [id])
        #expect(controller.isBlocked(id))
    }

    @Test("concurrent refreshes share one backend pass")
    func refreshCoalescesConcurrentCallers() async {
        let fake = FakeBlocklisting()
        fake.gated = true
        let controller = makeController(fake)

        async let first: Void = controller.refresh()
        async let second: Void = controller.refresh()

        // Hold the gate until the first pass has reached the backend and the second has
        // had every chance to open a pass of its own, so a pass it never started is the
        // coalescing working rather than the test releasing too early.
        while fake.calls == 0 { await Task.yield() }
        for _ in 0..<32 { await Task.yield() }
        fake.open()
        _ = await (first, second)

        #expect(fake.calls == 1)
    }

    @Test("a refresh after one finishes runs its own pass")
    func refreshAfterCompletionRefetches() async {
        let fake = FakeBlocklisting()
        let controller = makeController(fake)
        await controller.refresh()
        await controller.refresh()
        #expect(fake.calls == 2)
    }
}

@Suite("FlipBlocklisting profile resolution")
@MainActor
struct BlocklistResolutionTests {

    /// Resolves canned profiles, recording how many resolutions were ever in flight at
    /// once. Each one suspends, so a concurrent resolver overlaps them and a serial one
    /// cannot.
    @MainActor
    final class Resolver {
        private(set) var peakInFlight = 0
        private(set) var fetched: [UserID] = []
        private var inFlight = 0

        /// Users whose profile fetch fails.
        var failing: Set<UserID> = []
        /// Suspensions before a user's profile returns, used to make completion order
        /// differ from the order the entries came in.
        var suspensions: [UserID: Int] = [:]

        func fetch(_ userID: UserID) async throws -> Profile {
            fetched.append(userID)
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
            for _ in 0..<(suspensions[userID] ?? 2) { await Task.yield() }
            inFlight -= 1
            if failing.contains(userID) { throw URLError(.timedOut) }
            return Profile(displayName: "name-\(userID.uuidString.prefix(8))", phone: Optional<Phone>.none, email: nil)
        }
    }

    private func entries(_ count: Int) -> [BlockedUserEntry] {
        (0..<count).map {
            BlockedUserEntry(userID: UUID(), blockedAt: Date(timeIntervalSince1970: TimeInterval(1_000 - $0)))
        }
    }

    @Test("resolves profiles concurrently, up to the window")
    func resolvesConcurrently() async {
        let resolver = Resolver()
        let blocked = entries(12)

        let profiles = await FlipBlocklisting.resolve(blocked, concurrency: 4) { try await resolver.fetch($0) }

        #expect(profiles.count == 12)
        #expect(resolver.peakInFlight == 4)
    }

    @Test("keeps the server's order whatever order profiles come back in")
    func preservesServerOrder() async {
        let resolver = Resolver()
        let blocked = entries(6)
        // Earlier entries take longest, so completion order is the reverse of input order.
        for (index, entry) in blocked.enumerated() {
            resolver.suspensions[entry.userID] = (blocked.count - index) * 3
        }

        let profiles = await FlipBlocklisting.resolve(blocked, concurrency: 6) { try await resolver.fetch($0) }

        #expect(profiles.map(\.userID) == blocked.map(\.userID))
        #expect(profiles.map(\.blockedAt) == blocked.map(\.blockedAt))
    }

    @Test("fetches each blocked user exactly once")
    func fetchesEachUserOnce() async {
        let resolver = Resolver()
        let blocked = entries(9)

        _ = await FlipBlocklisting.resolve(blocked, concurrency: 4) { try await resolver.fetch($0) }

        #expect(Set(resolver.fetched) == Set(blocked.map(\.userID)))
        #expect(resolver.fetched.count == blocked.count)
    }

    @Test("a failed profile keeps the entry under the fallback name")
    func failedProfileKeepsEntry() async {
        let resolver = Resolver()
        let blocked = entries(3)
        resolver.failing = [blocked[1].userID]

        let profiles = await FlipBlocklisting.resolve(blocked, concurrency: 4) { try await resolver.fetch($0) }

        #expect(profiles.map(\.userID) == blocked.map(\.userID))
        #expect(profiles[1].displayName == ConversationController.fallbackCounterpartName)
        #expect(profiles[0].displayName != ConversationController.fallbackCounterpartName)
    }
}
