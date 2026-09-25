//
//  UserLinkCardTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// What a person card's lookup decides — whose link it is, and whether anyone owns it — and what the
/// card then says.
@MainActor
@Suite struct UserLinkCardTests {

    nonisolated private static let viewerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    nonisolated private static let otherID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    nonisolated private static let satoshi = Username("satoshi")!

    /// Answers every profile query from a fixed profile, and records which one was asked.
    private final class Profiles: ProfileReading, @unchecked Sendable {
        let profile: Profile
        private(set) var asked: [LinkCard.User.Identity] = []

        init(_ profile: Profile) { self.profile = profile }

        func fetchProfile(userID: UserID, owner: KeyPair) async throws -> Profile {
            asked.append(.userID(userID))
            return profile
        }

        func fetchProfile(username: Username, owner: KeyPair) async throws -> Profile {
            asked.append(.username(username))
            return profile
        }
    }

    private static func profile(
        userID: UserID? = otherID,
        displayName: String? = "Satoshi",
        username: Username? = satoshi,
        joinedAt: Date? = nil,
        fee: FiatAmount? = nil
    ) -> Profile {
        Profile(
            displayName: displayName,
            phone: Optional<Phone>.none,
            email: nil,
            joinedAt: joinedAt,
            userID: userID,
            username: username,
            minDmChatInitFee: fee
        )
    }

    private static func lookup(_ profiles: Profiles) throws -> @Sendable (LinkCard.User.Identity) async throws -> UserLinkFacts {
        LinkCardResolver.userLookup(profiles: profiles, viewer: try #require(KeyPair.generate()), viewerID: viewerID)
    }

    // MARK: - Lookup -

    @Test func aHandleLinkAsksByHandleAndAnIDLinkByID() async throws {
        let profiles = Profiles(Self.profile())
        let lookup = try Self.lookup(profiles)

        _ = try await lookup(.username(Self.satoshi))
        _ = try await lookup(.userID(Self.otherID))

        #expect(profiles.asked == [.username(Self.satoshi), .userID(Self.otherID)])
    }

    @Test func someoneElsesLinkIsNotOwn() async throws {
        let facts = try await Self.lookup(Profiles(Self.profile()))(.username(Self.satoshi))
        #expect(facts.userID == Self.otherID)
        #expect(!facts.isOwn)
    }

    /// Compared against the session's user, not the URL, so a handle link to the viewer counts too.
    @Test(arguments: [LinkCard.User.Identity.username(satoshi), .userID(viewerID)])
    func theViewersOwnLinkIsOwn(identity: LinkCard.User.Identity) async throws {
        let facts = try await Self.lookup(Profiles(Self.profile(userID: Self.viewerID)))(identity)
        #expect(facts.isOwn)
    }

    /// The server answers an unclaimed handle with an id-less empty profile rather than an error.
    @Test func anUnclaimedHandleIsNotFound() async throws {
        let lookup = try Self.lookup(Profiles(.empty))
        await #expect(throws: NoSuchAccount.self) { try await lookup(.username(Self.satoshi)) }
    }

    @Test func anUnclaimedHandleResolvesToNothing() async throws {
        let lookup = try Self.lookup(Profiles(.empty))
        let resolver = LinkCardResolver(
            cashLookup: { _ in throw CancellationError() },
            mintLookup: { _ in throw CancellationError() },
            groupLookup: { _ in throw CancellationError() },
            userLookup: lookup
        )
        #expect(await resolver.user(.username(Self.satoshi)) == nil)
    }

    /// A failed lookup draws the same card as an unclaimed handle, and is not remembered: the next
    /// appearance asks again.
    @Test func aFailedLookupResolvesToNothingAndAsksAgain() async throws {
        struct Offline: Error {}
        let calls = Calls()
        let resolver = LinkCardResolver(
            cashLookup: { _ in throw CancellationError() },
            mintLookup: { _ in throw CancellationError() },
            groupLookup: { _ in throw CancellationError() },
            userLookup: { _ in await calls.increment(); throw Offline() }
        )
        #expect(await resolver.user(.username(Self.satoshi)) == nil)
        #expect(await resolver.user(.username(Self.satoshi)) == nil)
        #expect(await calls.count == 2)
    }

    private actor Calls {
        var count = 0
        func increment() { count += 1 }
    }

    // MARK: - Card -

    private static func card(_ profile: Profile, isOwn: Bool = false) -> LinkCard.User.Resolved {
        userLinkCard(UserLinkFacts(profile: profile, userID: profile.userID!, isOwn: isOwn), imageData: nil)
    }

    @Test func theCardNamesThePersonAndTheirHandle() {
        let card = Self.card(Self.profile())
        #expect(card.displayName == "Satoshi")
        #expect(card.handle == "@satoshi")
        #expect(card.userID == Self.otherID)
    }

    @Test func aPersonWithNoHandleHasNoHandleLine() {
        let card = Self.card(Self.profile(username: nil))
        #expect(card.displayName == "Satoshi")
        #expect(card.handle == nil)
    }

    /// Named the way the profile screen names them: the handle stands in for a missing name, and is
    /// not repeated under itself.
    @Test func aPersonWithNoNameIsNamedByTheirHandle() {
        let card = Self.card(Self.profile(displayName: nil))
        #expect(card.displayName == "@satoshi")
        #expect(card.handle == nil)
    }

    @Test func theJoinedLineIsWordedAsOnTheProfileScreen() throws {
        let joined = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 3, day: 15)))
        let card = Self.card(Self.profile(joinedAt: joined))
        #expect(card.joined == "Joined \(joined.formatted(.dateTime.month(.wide).year()))")
        #expect(card.joined?.hasPrefix("Joined ") == true)
        #expect(card.joined?.contains("2024") == true)
    }

    @Test func noJoinDateMeansNoJoinedLine() {
        #expect(Self.profile(joinedAt: nil).joinedLine == nil)
        #expect(Self.card(Self.profile(joinedAt: nil)).joined == nil)
    }

    @Test func aFeeIsStatedAsTheMinimumToChat() {
        let card = Self.card(Self.profile(fee: .usd(1)))
        #expect(card.fee == "Minimum To Chat: \(FiatAmount.usd(1).formatted())")
    }

    @Test(arguments: [nil, FiatAmount.usd(0)])
    func noFeeMeansNoFeeLine(fee: FiatAmount?) {
        #expect(Self.card(Self.profile(fee: fee)).fee == nil)
    }
}
