import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite struct LinkCardResolverTests {

    private let card = LinkCard.Cash(
        url: URL(string: "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3")!,
        entropy: "KNi8pQr1n5hRU65vKJGge3",
        range: NSRange(location: 0, length: 54),
        state: .unresolved
    )

    private static let tokenCard = LinkCard.Token(
        url: URL(string: "https://app.flipcash.com/token/\(PublicKey.usdf.base58)")!,
        mint: .usdf,
        range: NSRange(location: 0, length: 74),
        state: .unresolved
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
        }
    ) -> LinkCardResolver {
        LinkCardResolver(cashLookup: cash, mintLookup: mint)
    }

    @Test func aFailedLookupStaysUnresolved() async throws {
        let resolver = Self.resolver(cash: { _ in throw Offline() })
        let resolved = await resolver.resolve(.cash(card))
        guard case .cash(let cash) = resolved else { Issue.record("not a cash card"); return }
        #expect(cash.state == .unresolved)
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
        let resolved = await resolver.resolve(.cash(card))
        guard case .cash(let cash) = resolved, case .resolved(let value) = cash.state else {
            Issue.record("card did not resolve"); return
        }
        #expect(value.amount == "$15.00")
    }

    @Test func theSameEntropyIsOnlyLookedUpOnce() async throws {
        let counter = Counter()
        let resolver = Self.resolver(cash: { _ in
            await counter.increment()
            throw Offline()
        })
        _ = await resolver.resolve(.cash(card))
        _ = await resolver.resolve(.cash(card))
        #expect(await counter.value == 1)
    }

    @Test func aTokenCardResolvesThroughTheMintLookup() async throws {
        let resolver = Self.resolver(mint: { _ in
            LinkCard.Token.Resolved(name: "Dollars", iconURL: nil, colors: ["#C4980B"], isReserve: true)
        })
        let resolved = await resolver.resolve(.token(Self.tokenCard))
        guard case .token(let token) = resolved, case .resolved(let value) = token.state else {
            Issue.record("card did not resolve"); return
        }
        #expect(value.name == "Dollars")
        #expect(value.isReserve)
    }

    @Test func anUnknownMintStaysUnresolvedRatherThanFailing() async throws {
        let resolver = Self.resolver(mint: { _ in throw Offline() })
        let resolved = await resolver.resolve(.token(Self.tokenCard))
        guard case .token(let token) = resolved else { Issue.record("not a token card"); return }
        #expect(token.state == .unresolved)
    }

    @Test func theSameMintIsOnlyLookedUpOnce() async throws {
        let counter = Counter()
        let resolver = Self.resolver(mint: { _ in
            await counter.increment()
            throw Offline()
        })
        _ = await resolver.resolve(.token(Self.tokenCard))
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

    @Test func aStateOfTheWrongKindIsIgnored() {
        let states: [String: LinkCard.State] = [
            LinkCard.cash(card).resolutionKey: .token(.resolved(
                LinkCard.Token.Resolved(name: "Dollars", iconURL: nil, colors: [], isReserve: true)
            ))
        ]
        let applied = LinkCard.cash(card).applying(states)
        #expect(applied.isUnresolved)
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
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
            mintLookup: { _ in throw Reader.Stop() }
        )

        let card = LinkCard.cash(
            LinkCard.Cash(
                url: URL(string: "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3")!,
                entropy: "KNi8pQr1n5hRU65vKJGge3",
                range: NSRange(location: 0, length: 54),
                state: .unresolved
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
            mintLookup: LinkCardResolver.mintLookup(reader: reader)
        )

        let card = LinkCard.token(
            LinkCard.Token(
                url: URL(string: "https://app.flipcash.com/token/\(PublicKey.usdf.base58)")!,
                mint: .usdf,
                range: NSRange(location: 0, length: 74),
                state: .unresolved
            )
        )
        _ = await resolver.resolve(card)

        #expect(reader.calls == [.usdf])
    }
}
