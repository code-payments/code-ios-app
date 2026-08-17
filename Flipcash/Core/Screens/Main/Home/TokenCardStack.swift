//
//  TokenCardStack.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// A vertical stack of ``TokenCardView``s that fans out (each card revealing its
/// `fannedReveal` header) and **collapses into its back card** as the enclosing
/// scroll view scrolls up — Apple Wallet style. Once the balance header has
/// scrolled off, the back card (index 0) reaches the top and pins there; the
/// remaining cards each collapse up into it in turn, tightening the fan from
/// `fannedReveal` to `collapsedReveal`. When the deck is fully collapsed it holds
/// briefly, then releases and scrolls off with the rest of the content.
///
/// Placement is driven entirely per-card by SwiftUI's `visualEffect`, reading
/// each card's own `frame(in: .scrollView).minY`. There is no shared scroll
/// state — the parent just renders the stack. The frame is reserved at the
/// *fanned* height so the scroll range stays stable while cards reposition.
struct TokenCardStack: View {

    /// Per-card reveal when the deck is fanned open (at rest).
    static let defaultFannedReveal: CGFloat = 64
    /// Per-card reveal when the deck is fully collapsed: 0, so the cards stack
    /// exactly and only the front card shows — the back cards hide completely
    /// behind it (no slivers), Apple Wallet style.
    static let defaultCollapsedReveal: CGFloat = 0
    /// How long (in scroll px) the fully-collapsed deck holds before releasing.
    static let defaultCollapsedHold: CGFloat = 24

    let items: [TokenCardData]
    var cardHeight: CGFloat = 224
    var fannedReveal: CGFloat = defaultFannedReveal
    var collapsedReveal: CGFloat = defaultCollapsedReveal
    /// Where the back card pins, measured from the top of the scroll viewport.
    var pinInset: CGFloat = 0
    /// Matched-transition namespace so the tapped card can zoom into the pushed
    /// currency-info hero card. `nil` disables the zoom source.
    var namespace: Namespace.ID? = nil
    /// The card being opened. The deck reorganises around it: the cards above it
    /// collapse into its slot, the rest push off the bottom.
    var expandingMint: PublicKey? = nil
    /// How far that reorganisation has run: 0 is the resting fan, 1 is fully
    /// cleared. The deck is driven by this scalar rather than by `expandingMint`
    /// alone because `visualEffect` interpolates a *value* that changes under an
    /// animation, but not a change of branch — toggling the mint swaps which
    /// formula applies, which resolves in a single frame and reads as a snap.
    var expansionProgress: CGFloat = 0
    /// Height of the enclosing scroll container, used to push the lower cards
    /// clear of the screen.
    var containerHeight: CGFloat = 0
    /// A card the stack must leave a hole for, because it is being drawn
    /// elsewhere: in flight between the deck and the page, or by the page itself.
    /// Outlives `expandingMint`, which clears as soon as closing starts.
    var hiddenMint: PublicKey? = nil
    /// Where the opened card comes to rest, leaving room for the chrome above it.
    var openTopInset: CGFloat = 0
    /// Reports the tapped card along with its current on-screen top edge, so the
    /// caller can work out the lift.
    var onCardTap: (TokenCardData, CGFloat) -> Void = { _, _ in }

    /// Each card's current top edge in global space, keyed by mint.
    @State private var cardTops: [PublicKey: CGFloat] = [:]

    private var expandingIndex: Int? {
        guard let expandingMint else { return nil }
        return items.firstIndex { $0.mint == expandingMint }
    }

    /// Always the fanned height, so the scroll range stays stable while cards collapse.
    private var stackHeight: CGFloat {
        items.isEmpty ? 0 : cardHeight + fannedReveal * CGFloat(items.count - 1)
    }

    private let collapsedHold: CGFloat = defaultCollapsedHold

    /// The stack-top position (in `.scrollView` space) at which the deck freezes
    /// and rides the scroll off: the last card's fully-collapsed point, less a
    /// short hold.
    private nonisolated var releaseTop: CGFloat {
        let lastIndex = CGFloat(max(items.count - 1, 0))
        let fullyCollapsed = pinInset - lastIndex * (fannedReveal - collapsedReveal)
        return fullyCollapsed - collapsedHold
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    onCardTap(item, cardTops[item.mint] ?? 0)
                } label: {
                    TokenCardView(data: item, height: cardHeight)
                }
                .buttonStyle(.plain)
                // Resting fan, and the reorganisation when a card is opened, are
                // both expressed here so they interpolate as one animation.
                .opacity(item.mint == hiddenMint ? 0 : 1)
                .visualEffect { [index, expandingIndex, containerHeight, expansionProgress, openTopInset] content, proxy in
                    let rect = proxy.frame(in: .scrollView)
                    let fan = offset(for: index, stackTop: rect.minY)

                    guard let expandingIndex, expansionProgress > 0 else {
                        return content.offset(y: fan).opacity(1)
                    }

                    // Where the opened card comes to rest. Every card is laid out
                    // at the same origin, so this is the same offset for all of
                    // them — the cards above gather onto exactly the spot the
                    // opened one lands, which is what makes them read as
                    // collapsing into it.
                    let open = openTopInset - rect.minY

                    // The opened card travels there and keeps its place in the
                    // deck's z-order the whole way. That ordering is what makes
                    // closing read as putting a card back: it slides under the
                    // cards on top of it rather than landing over them and then
                    // being covered in one frame when its z-order reverts. It
                    // also means the cards above gather *underneath* it.
                    if index == expandingIndex {
                        return content.offset(y: fan + (open - fan) * expansionProgress).opacity(1)
                    }

                    // The cards above collapse up into it, and the ones below run
                    // off the bottom; both fade on the way. Collapsing the upper
                    // cards *down* onto the opened card instead — by the reveal
                    // they each contribute — sends them the wrong way entirely
                    // when a card low in the deck is picked, dragging the whole
                    // top of the deck down over the card that is rising past it.
                    let cleared = index < expandingIndex ? open : containerHeight - rect.minY

                    return content
                        .offset(y: fan + (cleared - fan) * expansionProgress)
                        .opacity(1 - expansionProgress)
                }
                .onGeometryChange(for: CGFloat.self) { [index] proxy in
                    proxy.frame(in: .global).minY
                        + offset(for: index, stackTop: proxy.frame(in: .scrollView).minY)
                } action: { top in
                    cardTops[item.mint] = top
                }
                // Cards drawn front-to-back so the last (highest-value) sits on
                // top. The opened card keeps its natural place here — lifting it
                // above the deck would make it pop out on open and snap back
                // under on close.
                .zIndex(Double(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: stackHeight, alignment: .top)
    }

    /// Per-card vertical offset, relative to the card's own layout position (all
    /// cards are laid out coincident at the stack top, so every card sees the same
    /// `stackTop`). The fan, the collapse-into-back-card, and the release all fall
    /// out of this one input.
    ///
    /// - `stackTop` falls as the user scrolls up. While it's above `pinInset`, the
    ///   card rides at its fanned position. Once the card's fanned top would cross
    ///   its collapsed slot (`pinInset + index · collapsedReveal`), it pins there —
    ///   the back card first, then each card in turn. Below `releaseTop` the input
    ///   is clamped, freezing the offset so the collapsed deck scrolls off.
    private nonisolated func offset(for index: Int, stackTop: CGFloat) -> CGFloat {
        let fannedY = CGFloat(index) * fannedReveal
        let collapsedSlot = pinInset + CGFloat(index) * collapsedReveal
        let effectiveTop = max(stackTop, releaseTop)
        let restingTop = max(effectiveTop + fannedY, collapsedSlot)
        return restingTop - effectiveTop
    }
}

/// Marks a card as the morph source for the detail's hero card, but only when
/// the stack was given a namespace — it renders fine standalone (previews).
private struct WalletCardTransitionSource: ViewModifier {
    let mint: PublicKey
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: mint, in: namespace)
        } else {
            content
        }
    }
}
