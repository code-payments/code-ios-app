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
    var onCardTap: (TokenCardData) -> Void = { _ in }

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
                    onCardTap(item)
                } label: {
                    TokenCardView(data: item, height: cardHeight)
                }
                .buttonStyle(.plain)
                // Separate stacked cards so a card's rounded top corners read as
                // sitting above the card behind, not bleeding its color/border through.
                .shadow(color: .black.opacity(0.35), radius: 8, y: -2)
                .visualEffect { [index] content, proxy in
                    content.offset(y: offset(for: index, stackTop: proxy.frame(in: .scrollView).minY))
                }
                // Cards drawn front-to-back so the last (highest-value) sits on top.
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
