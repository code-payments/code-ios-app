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

    private struct Offline: Error {}

    @Test func aFailedLookupStaysUnresolved() async throws {
        let resolver = LinkCardResolver { _ in throw Offline() }
        let resolved = await resolver.resolve(.cash(card))
        guard case .cash(let cash) = resolved else { Issue.record("not a cash card"); return }
        #expect(cash.state == .unresolved)
    }

    @Test func aSuccessfulLookupFillsTheCardIn() async throws {
        let resolver = LinkCardResolver { _ in
            LinkCard.Cash.Resolved(
                amount: "$15.00",
                claim: .claimable,
                tokenName: "Dollars",
                iconURL: nil,
                billColors: [],
                isUSDF: true,
                issuedByViewer: false
            )
        }
        let resolved = await resolver.resolve(.cash(card))
        guard case .cash(let cash) = resolved, case .resolved(let value) = cash.state else {
            Issue.record("card did not resolve"); return
        }
        #expect(value.amount == "$15.00")
    }

    @Test func theSameEntropyIsOnlyLookedUpOnce() async throws {
        let counter = Counter()
        let resolver = LinkCardResolver { _ in
            await counter.increment()
            throw Offline()
        }
        _ = await resolver.resolve(.cash(card))
        _ = await resolver.resolve(.cash(card))
        #expect(await counter.value == 1)
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
            lookup: LinkCardResolver.giftCardLookup(reader: reader, viewer: viewer)
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
