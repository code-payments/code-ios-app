//
//  LinkCardViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// The card looks its own link up now, from inside a recycled row. What that has to get right is
/// what these pin: shimmer while nothing is known, paint what arrives, and never paint one link's
/// answer onto the row that has moved on to another.
@MainActor
@Suite("LinkCardView")
struct LinkCardViewTests {

    /// Hands out streams the test drives by hand, and remembers which of them the view let go of.
    private final class Source: LinkCardSource {

        // Keyed on the card rather than on the app target's resolution key, which this module
        // cannot see and does not need: a card is the link's identity either way.
        var answers: [LinkCard: LinkCard.State] = [:]
        private(set) var asked: [LinkCard] = []
        private(set) var dropped: [LinkCard] = []
        private var continuations: [LinkCard: AsyncStream<LinkCard.State>.Continuation] = [:]

        func known(_ card: LinkCard) -> LinkCard.State? {
            answers[card]
        }

        func states(for card: LinkCard) -> AsyncStream<LinkCard.State> {
            asked.append(card)
            let (stream, continuation) = AsyncStream<LinkCard.State>.makeStream()
            continuations[card] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.dropped.append(card) }
            }
            return stream
        }

        func yield(_ state: LinkCard.State, for card: LinkCard) {
            continuations[card]?.yield(state)
        }
    }

    private static func cashCard(_ entropy: String) -> LinkCard {
        .cash(
            LinkCard.Cash(
                url: URL(string: "https://send.flipcash.com/c/#/e=\(entropy)")!,
                entropy: entropy,
                range: NSRange(location: 0, length: 54)
            )
        )
    }

    private static func resolved(_ amount: String, claim: LinkCard.Cash.Claim = .claimed) -> LinkCard.State {
        .cash(.resolved(
            LinkCard.Cash.Resolved(amount: amount, claim: claim, tokenName: "Dollars", iconURL: nil)
        ))
    }

    /// The view subscribes on configure, so the paint the stream drives lands a turn later.
    private func settle(until condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func isShimmering(_ view: LinkCardView) -> Bool {
        guard let cash = view.descendants(of: LinkCashCardView.self).first else { return false }
        return cash.descendants(of: LinkCardShimmerView.self).contains { !$0.isHidden }
    }

    private func texts(_ view: LinkCardView) -> [String] {
        guard let cash = view.descendants(of: LinkCashCardView.self).first else { return [] }
        return cash.descendants(of: UILabel.self).compactMap(\.text)
    }

    @Test("A card with nothing known shimmers until its answer arrives")
    func unknownCard_shimmersThenPaints() async {
        let source = Source()
        let view = LinkCardView()
        let card = Self.cashCard("abc")

        view.configure(with: card, source: source)
        #expect(isShimmering(view))
        #expect(source.asked == [card])

        source.yield(Self.resolved("$15.00"), for: card)

        #expect(await settle { self.texts(view).contains("$15.00") })
        #expect(!isShimmering(view))
    }

    @Test("A remembered answer paints straight away, with no shimmer")
    func knownCard_paintsWithoutShimmering() {
        let source = Source()
        let card = Self.cashCard("abc")
        source.answers[card] = Self.resolved("$15.00")

        let view = LinkCardView()
        view.configure(with: card, source: source)

        #expect(!isShimmering(view))
        #expect(texts(view).contains("$15.00"))
    }

    /// A subscription outliving its card is the one way this architecture can paint a lie: the row
    /// is recycled, another link is in it, and the first link's answer arrives.
    @Test("A recycled row ignores the card it used to hold")
    func recycledRow_ignoresThePreviousCardsAnswer() async {
        let source = Source()
        let first = Self.cashCard("first")
        let second = Self.cashCard("second")

        let view = LinkCardView()
        view.configure(with: first, source: source)
        view.prepareForReuse()
        view.configure(with: second, source: source)

        #expect(await settle { source.dropped == [first] })

        source.yield(Self.resolved("$15.00"), for: first)
        source.yield(Self.resolved("$2.00"), for: second)

        #expect(await settle { self.texts(view).contains("$2.00") })
        #expect(!texts(view).contains("$15.00"))
    }

    /// The claim is offered from the first frame and survives a lookup that fails, matching
    /// Android. It is honest rather than optimistic because the tap is live in every state — the
    /// bubble opens the link without consulting resolution — so the pill labels a control that
    /// already works.
    @Test("A card that has not resolved still offers the claim")
    func unresolvedCard_offersTheClaimFromTheFirstFrame() async {
        let source = Source()
        let view = LinkCardView()
        let card = Self.cashCard("abc")

        view.configure(with: card, source: source)
        #expect(texts(view).contains("Tap to claim"))

        source.yield(.cash(.unresolved), for: card)

        #expect(await settle { !self.isShimmering(view) })
        #expect(texts(view).contains("Tap to claim"), "a failed lookup leaves the offer standing")
    }

    /// The other half of that trade: a link already spent withdraws the offer when the answer
    /// lands, onto a card that says what happened to it.
    @Test("A link that comes back claimed withdraws the offer")
    func claimedCard_withdrawsTheOffer() async {
        let source = Source()
        let view = LinkCardView()
        let card = Self.cashCard("abc")

        view.configure(with: card, source: source)
        source.yield(Self.resolved("$15.00", claim: .claimed), for: card)

        #expect(await settle { self.texts(view).contains("Claimed") })
        #expect(!texts(view).contains("Tap to claim"))
    }

    /// What a preview or a test that does not care about resolution gets: the card the link itself
    /// describes, and nothing pretending to be on its way.
    @Test("With no source the card paints unresolved and does not shimmer")
    func noSource_paintsUnresolved() {
        let view = LinkCardView()
        view.configure(with: Self.cashCard("abc"), source: nil)
        #expect(!isShimmering(view))
    }
}
