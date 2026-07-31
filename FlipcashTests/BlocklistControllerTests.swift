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
        func getBlockedUserProfiles() async throws -> [BlockedUserProfile] {
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
}
