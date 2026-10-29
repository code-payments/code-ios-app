//
//  CurrencyInfoViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// Pins the loading-state churn behavior behind the Wallet → Currency Info
/// AppHang: redundant `loadingState` reassignments re-render the whole screen
/// (including the navigation-bar principal item) mid-transition.
@MainActor
@Suite("CurrencyInfoViewModel loading-state churn")
struct CurrencyInfoViewModelTests {

    private func makeViewModel(
        seeding metadata: MintMetadata
    ) throws -> (viewModel: CurrencyInfoViewModel, database: Database) {
        let database = Database.mock
        try database.insert(mints: [metadata], date: .now)

        let ratesController = RatesController(container: .mock, database: database)
        let session = Session.makeMock(database: database, ratesController: ratesController)

        let viewModel = CurrencyInfoViewModel(
            mint: metadata.address,
            session: session,
            database: database,
            ratesController: ratesController
        )
        return (viewModel, database)
    }

    /// Bounded window for the `Updateable` notification hop
    /// (`Task { @MainActor ... }`) to run when the expected outcome is that
    /// nothing happens — a negative can't be awaited, only outwaited.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test("Cached entry: loadMintMetadata does not invalidate loadingState")
    func loadMintMetadata_cachedUnchangedRow_doesNotInvalidate() async throws {
        let (viewModel, _) = try makeViewModel(seeding: .makeLaunchpad())
        #expect(viewModel.isLoaded)

        await confirmation("loadingState invalidated", expectedCount: 0) { invalidated in
            withObservationTracking {
                _ = viewModel.loadingState
            } onChange: {
                invalidated()
            }
            await viewModel.loadMintMetadata()
        }
    }

    @Test("A database change that leaves the row identical does not invalidate loadingState")
    func databaseChange_identicalRow_doesNotInvalidate() async throws {
        let metadata = MintMetadata.makeLaunchpad()
        let (viewModel, database) = try makeViewModel(seeding: metadata)
        await viewModel.loadMintMetadata()

        // A no-op poll: same content, later date. The write gate keeps the
        // stored row byte-identical, so the requery must compare equal.
        try database.insert(mints: [metadata], date: .now + 60)

        try await confirmation("loadingState invalidated", expectedCount: 0) { invalidated in
            withObservationTracking {
                _ = viewModel.loadingState
            } onChange: {
                invalidated()
            }
            NotificationCenter.default.post(name: .databaseDidChange, object: nil)
            try await settle()
        }
    }

    @Test("A real supply change still updates loadingState")
    func databaseChange_supplyChanged_updates() async throws {
        let metadata = MintMetadata.makeLaunchpad(supplyFromBonding: 100)
        let (viewModel, database) = try makeViewModel(seeding: metadata)
        await viewModel.loadMintMetadata()

        try database.updateLiveSupply(
            updates: [ReserveStateUpdate(mint: metadata.address, supplyFromBonding: 999)],
            date: .now
        )
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)

        try await waitUntil(viewModel) { $0.mintMetadata?.supplyFromBonding == 999 }
    }
}

@MainActor
@Suite("CurrencyInfoViewModel community leader")
struct CurrencyInfoViewModelCommunityLeaderTests {

    private static let leaderID = UUID()

    private static func leader(displayName: String? = "Jeff Yanta", username: String? = "jeff", userID: UserID? = leaderID) -> Profile {
        Profile(
            displayName: displayName,
            phone: Optional<Phone>.none,
            email: nil,
            userID: userID,
            username: username.flatMap(Username.init)
        )
    }

    private static func chat() -> Conversation {
        Conversation(id: .test(1), members: [], lastMessage: nil, lastActivity: .now, type: .group)
    }

    private func makeViewModel(
        mint: PublicKey = MintMetadata.makeLaunchpad().address,
        fetcher: MockSession
    ) -> CurrencyInfoViewModel {
        let database = Database.mock
        let ratesController = RatesController(container: .mock, database: database)
        return CurrencyInfoViewModel(
            mint: mint,
            session: Session.makeMock(database: database, ratesController: ratesController),
            database: database,
            ratesController: ratesController,
            communityFetcher: fetcher
        )
    }

    @Test("A leader with a name, username, photo and user id is shown alongside the chats")
    func leaderWithChats_isShown() async {
        let fetcher = MockSession()
        fetcher.fetchCommunityHandler = { mint in
            Community(mint: mint, name: "Jeffy", leader: Self.leader(), topHolderChats: [Self.chat()])
        }
        let viewModel = makeViewModel(fetcher: fetcher)

        await viewModel.loadCommunityChats()

        #expect(viewModel.communityLeader == Self.leader())
        #expect(viewModel.communityLeader?.userID == Self.leaderID)
        #expect(viewModel.communityChats.count == 1)
    }

    @Test("A leader is shown when there are no ranked chats")
    func leaderWithoutChats_isShown() async {
        let fetcher = MockSession()
        fetcher.fetchCommunityHandler = { mint in
            Community(mint: mint, name: "Jeffy", leader: Self.leader(), topHolderChats: [])
        }
        let viewModel = makeViewModel(fetcher: fetcher)

        await viewModel.loadCommunityChats()

        #expect(viewModel.communityLeader == Self.leader())
        #expect(viewModel.communityChats.isEmpty)
    }

    @Test("No leader on the community shows no section")
    func leaderUnset_isHidden() async {
        let fetcher = MockSession()
        fetcher.fetchCommunityHandler = { mint in
            Community(mint: mint, name: "Jeffy", leader: nil, topHolderChats: [Self.chat()])
        }
        let viewModel = makeViewModel(fetcher: fetcher)

        await viewModel.loadCommunityChats()

        #expect(viewModel.communityLeader == nil)
    }

    @Test("A leader without a display name counts as no leader", arguments: [nil, ""] as [String?])
    func leaderWithoutDisplayName_isHidden(displayName: String?) async {
        let fetcher = MockSession()
        fetcher.fetchCommunityHandler = { mint in
            Community(mint: mint, name: "Jeffy", leader: Self.leader(displayName: displayName), topHolderChats: [])
        }
        let viewModel = makeViewModel(fetcher: fetcher)

        await viewModel.loadCommunityChats()

        #expect(viewModel.communityLeader == nil)
    }

    @Test("A failed GetCommunity clears a leader shown earlier")
    func fetchFails_clearsLeader() async {
        let fetcher = MockSession()
        fetcher.fetchCommunityHandler = { mint in
            Community(mint: mint, name: "Jeffy", leader: Self.leader(), topHolderChats: [Self.chat()])
        }
        let viewModel = makeViewModel(fetcher: fetcher)
        await viewModel.loadCommunityChats()
        #expect(viewModel.communityLeader != nil)

        fetcher.fetchCommunityHandler = { _ in throw URLError(.notConnectedToInternet) }
        await viewModel.loadCommunityChats()

        #expect(viewModel.communityLeader == nil)
        #expect(viewModel.communityChats.isEmpty)
    }

    @Test("USDF shows no leader and makes no GetCommunity call")
    func usdf_skipsFetch() async {
        let fetcher = MockSession()
        var calls = 0
        fetcher.fetchCommunityHandler = { mint in
            calls += 1
            return Community(mint: mint, name: "USDF", leader: Self.leader(), topHolderChats: [Self.chat()])
        }
        let viewModel = makeViewModel(mint: .usdf, fetcher: fetcher)

        await viewModel.loadCommunityChats()

        #expect(calls == 0)
        #expect(viewModel.communityLeader == nil)
        #expect(viewModel.communityChats.isEmpty)
    }
}

@Suite("CommunityLeader row text")
struct CommunityLeaderTextTests {

    private static func leader(username: String?) -> Profile {
        Profile(displayName: "Jeff Yanta", phone: Optional<Phone>.none, email: nil, username: username.flatMap(Username.init))
    }

    @Test("The subtitle is the @username, or nothing without one")
    func subtitle() {
        #expect(CommunityLeader.subtitle(for: Self.leader(username: "jeff")) == "@jeff")
        #expect(CommunityLeader.subtitle(for: Self.leader(username: nil)) == nil)
    }

    @Test("The label says the row opens the profile only when it can")
    func accessibilityLabel() {
        let leader = Self.leader(username: "jeff")
        #expect(CommunityLeader.accessibilityLabel(for: leader, isTappable: true) == "Community Leader, Jeff Yanta, @jeff. Opens profile.")
        #expect(CommunityLeader.accessibilityLabel(for: leader, isTappable: false) == "Community Leader, Jeff Yanta, @jeff")
        #expect(CommunityLeader.accessibilityLabel(for: Self.leader(username: nil), isTappable: false) == "Community Leader, Jeff Yanta")
    }
}
