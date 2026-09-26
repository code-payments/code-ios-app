import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite struct LinkCardResolverTests {

    private let card = LinkCard.Cash(
        url: URL(string: "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3")!,
        entropy: "KNi8pQr1n5hRU65vKJGge3",
        range: NSRange(location: 0, length: 54)
    )

    private static let tokenCard = LinkCard.Token(
        url: URL(string: "https://app.flipcash.com/token/\(PublicKey.usdf.base58)")!,
        mint: .usdf,
        range: NSRange(location: 0, length: 74)
    )

    private struct Offline: Error {}

    /// The kind under test supplies its lookup; the other one traps, so a test that crosses the two
    /// caches fails loudly instead of quietly returning the wrong card.
    private static func resolver(
        cash: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved = { _ in
            Issue.record("the cash lookup was called"); throw Offline()
        },
        mint: @escaping @Sendable (PublicKey) async throws -> LinkCard.Token.Resolved = { _ in
            Issue.record("the mint lookup was called"); throw Offline()
        },
        group: @escaping @Sendable (ConversationID) async throws -> GroupLinkFacts = { _ in
            Issue.record("the group lookup was called"); throw Offline()
        },
        user: @escaping @Sendable (LinkCard.User.Identity) async throws -> UserLinkFacts = { _ in
            Issue.record("the user lookup was called"); throw Offline()
        }
    ) -> LinkCardResolver {
        LinkCardResolver(cashLookup: cash, mintLookup: mint, groupLookup: group, userLookup: user)
    }

    @Test func aFailedLookupStaysUnresolved() async throws {
        let resolver = Self.resolver(cash: { _ in throw Offline() })
        #expect(await resolver.resolve(.cash(card)) == .cash(.unresolved))
    }

    @Test func aSuccessfulLookupFillsTheCardIn() async throws {
        let resolver = Self.resolver(cash: { _ in
            LinkCard.Cash.Resolved(
                amount: "$15.00",
                claim: .claimable,
                tokenName: "Dollars",
                iconURL: nil
            )
        })
        guard case .cash(.resolved(let value)) = await resolver.resolve(.cash(card)) else {
            Issue.record("card did not resolve"); return
        }
        #expect(value.amount == "$15.00")
    }

    @Test func theSameEntropyIsOnlyLookedUpOnce() async throws {
        let counter = Counter()
        let resolver = Self.resolver(cash: { _ in
            await counter.increment()
            return LinkCard.Cash.Resolved(
                amount: "$15.00",
                claim: .claimed,
                tokenName: "Dollars",
                iconURL: nil
            )
        })
        _ = await resolver.resolve(.cash(card))
        _ = await resolver.resolve(.cash(card))
        #expect(await counter.value == 1)
    }

    /// The one answer that is not kept. A card whose lookup failed while the phone was in a lift
    /// would otherwise stay blank for as long as the session lives, which is what holding a failure
    /// costs and why neither platform does it.
    @Test func aFailedLookupIsForgottenSoTheNextAskGoesBackOut() async throws {
        let counter = Counter()
        let resolver = Self.resolver(cash: { _ in
            await counter.increment()
            throw Offline()
        })
        _ = await resolver.resolve(.cash(card))
        _ = await resolver.resolve(.cash(card))
        #expect(await counter.value == 2)
    }

    @Test func aTokenCardResolvesThroughTheMintLookup() async throws {
        let resolver = Self.resolver(mint: { _ in
            LinkCard.Token.Resolved(name: "Dollars", iconURL: nil, colors: ["#C4980B"], isReserve: true)
        })
        guard case .token(.resolved(let value)) = await resolver.resolve(.token(Self.tokenCard)) else {
            Issue.record("card did not resolve"); return
        }
        #expect(value.name == "Dollars")
        #expect(value.isReserve)
    }

    @Test func anUnknownMintStaysUnresolvedRatherThanFailing() async throws {
        let resolver = Self.resolver(mint: { _ in throw Offline() })
        #expect(await resolver.resolve(.token(Self.tokenCard)) == .token(.unresolved))
    }

    @Test func theSameMintIsOnlyLookedUpOnce() async throws {
        let counter = Counter()
        let resolver = Self.resolver(mint: { _ in
            await counter.increment()
            return LinkCard.Token.Resolved(name: "Dollars", iconURL: nil, colors: [], isReserve: true)
        })
        _ = await resolver.resolve(.token(Self.tokenCard))
        _ = await resolver.resolve(.token(Self.tokenCard))
        #expect(await counter.value == 1)
    }

    /// Two rows quoting one link, both asking before either answer is back. The resolver memoizes
    /// the query rather than the answer for this: an actor serializes turns, not awaits, so a cache
    /// of answers would have both callers miss and both query.
    @Test func twoCallersAskingAtOnceShareOneQuery() async throws {
        let counter = Counter()
        let gate = Gate()
        let resolver = Self.resolver(cash: { _ in
            await counter.increment()
            await gate.wait()
            return LinkCard.Cash.Resolved(
                amount: "$15.00",
                claim: .claimed,
                tokenName: "Dollars",
                iconURL: nil
            )
        })

        async let first = resolver.resolve(.cash(card))
        // The second caller can only find the first one's query once it exists, so the gate holds
        // the lookup open until the counter says it has started.
        while await counter.value == 0 { await Task.yield() }
        async let second = resolver.resolve(.cash(card))
        await gate.open()

        _ = await (first, second)
        #expect(await counter.value == 1)
    }

    /// A claim settles and the memo is wrong — this is the only way back to the server for it.
    @Test func invalidatingACashLinkAsksAgain() async throws {
        let counter = Counter()
        let resolver = Self.resolver(cash: { _ in
            await counter.increment()
            return LinkCard.Cash.Resolved(
                amount: "$15.00",
                claim: await counter.value == 1 ? .claimable : .claimed,
                tokenName: "Dollars",
                iconURL: nil
            )
        })

        _ = await resolver.resolve(.cash(card))
        await resolver.invalidateCash(entropy: card.entropy)
        let again = await resolver.resolve(.cash(card))

        guard case .cash(.resolved(let value)) = again else {
            Issue.record("card did not resolve"); return
        }
        #expect(await counter.value == 2)
        #expect(value.claim == .claimed)
    }

    /// The caches are separate, and invalidation has to respect that: a mint's branding does not
    /// settle, so a claim has no business dropping it.
    @Test func invalidatingACashLinkLeavesTheMintCacheAlone() async throws {
        let counter = Counter()
        let resolver = Self.resolver(
            cash: { _ in throw Offline() },
            mint: { _ in
                await counter.increment()
                return LinkCard.Token.Resolved(name: "Dollars", iconURL: nil, colors: [], isReserve: true)
            }
        )

        _ = await resolver.resolve(.token(Self.tokenCard))
        await resolver.invalidateCash(entropy: card.entropy)
        _ = await resolver.resolve(.token(Self.tokenCard))

        #expect(await counter.value == 1)
    }

    /// The two kinds share one dictionary on the way back to the transcript, so their keys have to
    /// stay apart even when a mint address and an entropy read alike.
    @Test func aCashAndATokenCardNeverShareAResolutionKey() {
        #expect(LinkCard.cash(card).resolutionKey != LinkCard.token(Self.tokenCard).resolutionKey)
        #expect(LinkCard.cash(card).resolutionKey.hasPrefix("cash:"))
        #expect(LinkCard.token(Self.tokenCard).resolutionKey.hasPrefix("token:"))
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    /// Holds a lookup open until the test says otherwise, so two callers are provably in flight at
    /// the same moment rather than merely likely to be.
    private actor Gate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            isOpen = true
            continuations.forEach { $0.resume() }
            continuations = []
        }
    }
}

@Suite struct GiftCardLookupTests {

    /// Records the one call it is allowed to receive, then fails. What is under test is which call
    /// the lookup makes, not what comes back — and throwing avoids standing up an `AccountInfo`
    /// fixture that would need updating every time that model grows a field.
    private nonisolated final class Reader: GiftCardAccountReading, @unchecked Sendable {
        var calls: [(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?)] = []
        struct Stop: Error {}

        func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?) async throws -> AccountInfo {
            calls.append((type, owner, requestingOwner))
            throw Stop()
        }
    }

    @Test func resolvingACardReadsTheGiftCardAccountAndNothingElse() async throws {
        let reader = Reader()
        let viewer = try #require(KeyPair.generate())
        let resolver = LinkCardResolver(
            cashLookup: LinkCardResolver.giftCardLookup(reader: reader, viewer: viewer),
            mintLookup: { _ in throw Reader.Stop() },
            groupLookup: { _ in throw Reader.Stop() },
            userLookup: { _ in throw Reader.Stop() }
        )

        let card = LinkCard.cash(
            LinkCard.Cash(
                url: URL(string: "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3")!,
                entropy: "KNi8pQr1n5hRU65vKJGge3",
                range: NSRange(location: 0, length: 54)
            )
        )
        _ = await resolver.resolve(card)

        #expect(reader.calls.count == 1)
        #expect(reader.calls.first?.type == .giftCard)
        #expect(reader.calls.first?.requestingOwner == viewer)
        #expect(reader.calls.first?.owner != viewer, "the gift card is looked up under its own key")
    }
}

@Suite struct MintLookupTests {

    /// Records the mint it is asked for, then fails — the same shape as `Reader` above and for the
    /// same reason: what is under test is which call the lookup makes.
    private nonisolated final class Reader: MintMetadataReading, @unchecked Sendable {
        var calls: [PublicKey] = []
        struct Stop: Error {}

        func fetchMint(mint: PublicKey) async throws -> MintMetadata {
            calls.append(mint)
            throw Stop()
        }
    }

    @Test func resolvingATokenCardAsksForThatMint() async throws {
        let reader = Reader()
        let resolver = LinkCardResolver(
            cashLookup: { _ in throw Reader.Stop() },
            mintLookup: LinkCardResolver.mintLookup(reader: reader),
            groupLookup: { _ in throw Reader.Stop() },
            userLookup: { _ in throw Reader.Stop() }
        )

        let card = LinkCard.token(
            LinkCard.Token(
                url: URL(string: "https://app.flipcash.com/token/\(PublicKey.usdf.base58)")!,
                mint: .usdf,
                range: NSRange(location: 0, length: 74)
            )
        )
        _ = await resolver.resolve(card)

        #expect(reader.calls == [.usdf])
    }
}
