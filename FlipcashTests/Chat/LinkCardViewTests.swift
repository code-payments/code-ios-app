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

    // MARK: - Web

    private static let attachment = MediaAttachment(
        blobID: BlobID(data: Data(repeating: 7, count: 16)), width: 1200, height: 630, blurhash: nil
    )

    private static func webCard(
        _ url: String = "https://example.com/a",
        description: String? = "About it",
        image: MediaAttachment? = nil
    ) -> LinkCard {
        .web(LinkCard.Web(
            url: URL(string: url)!,
            range: NSRange(location: 0, length: (url as NSString).length),
            page: MessageLinkPreview(url: url, title: "Example Title", description: description, image: image)
        ))
    }

    private func web(_ view: LinkCardView) -> LinkWebCardView? {
        view.descendants(of: LinkWebCardView.self).first
    }

    @Test("A web card draws the page its message carries, with no source")
    func web_drawsTheSentPage() {
        let view = LinkCardView(frame: CGRect(x: 0, y: 0, width: 240, height: 0))
        view.configure(with: Self.webCard(), source: nil)
        #expect(web(view)?.titleLabel.text == "Example Title")
        #expect(web(view)?.hostLabel.text == "example.com")
    }

    @Test("A web card never asks the source")
    func web_neverAsksTheSource() async {
        let source = Source()
        let view = LinkCardView(frame: CGRect(x: 0, y: 0, width: 240, height: 0))
        view.configure(with: Self.webCard(), source: source)
        for _ in 0..<10 { await Task.yield() }
        #expect(source.asked.isEmpty)
    }

    @Test("The host strips a leading www.")
    func web_host_stripsWWW() {
        let view = LinkCardView(frame: CGRect(x: 0, y: 0, width: 240, height: 0))
        view.configure(with: Self.webCard("https://www.example.com/a"), source: nil)
        #expect(web(view)?.hostLabel.text == "example.com")
    }

    // MARK: - Web image slot

    private static let pageWithImage = LinkWebCardView.Page(
        host: "example.com", title: "Example Title", description: nil, image: attachment
    )

    private static let pageWithoutImage = LinkWebCardView.Page(
        host: "example.com", title: "Example Title", description: nil, image: nil
    )

    /// A card whose image load waits until the test hands it an image, or nil for a failure.
    private func imageCard() -> (LinkWebCardView, AsyncStream<UIImage?>.Continuation) {
        let (stream, continuation) = AsyncStream<UIImage?>.makeStream()
        let view = LinkWebCardView(frame: CGRect(x: 0, y: 0, width: 240, height: 0))
        view.loadImage = { _ in
            for await image in stream { return image }
            return nil
        }
        return (view, continuation)
    }

    private static let pixel = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1))
        .image { $0.fill(CGRect(x: 0, y: 0, width: 2, height: 1)) }

    private func isLoading(_ view: LinkWebCardView) -> Bool {
        if case .loading = view.imageSlot { return true }
        return false
    }

    @Test("A preview with an image holds the image's slot while it loads")
    func webImage_loading_holdsTheSlot() {
        let (view, _) = imageCard()
        view.configure(with: .preview(Self.pageWithImage))
        #expect(isLoading(view))
    }

    @Test("A loaded image fills the slot it held")
    func webImage_loaded_fillsTheSlot() async {
        let (view, continuation) = imageCard()
        view.configure(with: .preview(Self.pageWithImage))
        continuation.yield(Self.pixel)
        for _ in 0..<50 where isLoading(view) { await Task.yield() }
        guard case .loaded = view.imageSlot else {
            Issue.record("expected a loaded image, got \(view.imageSlot)")
            return
        }
    }

    @Test("A failed image drops its slot and reports the height change")
    func webImage_failed_dropsTheSlot() async {
        let (view, continuation) = imageCard()
        var changes = 0
        view.onImageChange = { changes += 1 }
        view.configure(with: .preview(Self.pageWithImage))
        continuation.yield(nil)
        for _ in 0..<50 where isLoading(view) { await Task.yield() }
        guard case .none = view.imageSlot else {
            Issue.record("expected no slot, got \(view.imageSlot)")
            return
        }
        #expect(changes == 1)
    }

    @Test("An image already in memory fills the slot on the first frame (P22a)")
    func webImage_cached_drawsOnFirstFrame() {
        let (view, _) = imageCard()
        view.cachedImage = { $0 == Self.attachment ? Self.pixel : nil }
        view.configure(with: .preview(Self.pageWithImage))
        guard case .loaded = view.imageSlot else {
            Issue.record("expected the cached image on the first frame, got \(view.imageSlot)")
            return
        }
    }

    @Test("An image not in memory still holds the slot while it loads")
    func webImage_cacheMiss_holdsTheSlot() {
        let (view, _) = imageCard()
        view.cachedImage = { _ in nil }
        view.configure(with: .preview(Self.pageWithImage))
        #expect(isLoading(view))
    }

    @Test("A preview with no image takes no slot")
    func webImage_absent_takesNoSlot() {
        let (view, _) = imageCard()
        view.configure(with: .preview(Self.pageWithoutImage))
        guard case .none = view.imageSlot else {
            Issue.record("expected no slot, got \(view.imageSlot)")
            return
        }
    }
}
