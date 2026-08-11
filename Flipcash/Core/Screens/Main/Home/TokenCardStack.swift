//
//  TokenCardStack.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// A vertical stack of ``TokenCardView``s that fans out (each card revealing its
/// `fannedReveal` header) and **collapses, then scrolls off** as the enclosing
/// scroll view scrolls up: cards pin at the top and tighten from the fanned gap
/// to `collapsedReveal` (a growing deck); once fully collapsed the deck releases
/// and scrolls off with the rest of the content. Ported from Android's
/// `TokenCardStack` custom `Layout` — reimplemented with `offset` placement so it
/// works on the iOS 15 deployment target (which predates SwiftUI's `Layout`).
///
/// The measured height is always the *fanned* height, so the enclosing scroll
/// view's range is stable — cards are only repositioned, never resized.
/// `scrolledPast` is the px the stack's top has scrolled above the viewport top;
/// the parent measures it and passes it in (see `WalletScreen`).
struct TokenCardStack: View {

    let items: [TokenCardData]
    var cardHeight: CGFloat = 224
    var fannedReveal: CGFloat = 64
    var collapsedReveal: CGFloat = 12
    var pinInset: CGFloat = 0
    var scrolledPast: CGFloat = 0
    var onCardTap: (TokenCardData) -> Void = { _ in }

    /// Always the fanned height, so the scroll range stays stable while cards collapse.
    private var stackHeight: CGFloat {
        items.isEmpty ? 0 : cardHeight + fannedReveal * CGFloat(items.count - 1)
    }

    /// Scroll distance at which every card has finished collapsing (the last pins last).
    private var collapseComplete: CGFloat {
        max(0, CGFloat(items.count - 1) * (fannedReveal - collapsedReveal) - pinInset)
    }

    var body: some View {
        // Cap `past` at collapseComplete: once fully collapsed the deck stops
        // pinning and the frozen layout scrolls off with the content.
        let past = min(max(scrolledPast, 0), collapseComplete)
        ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let fannedY = CGFloat(index) * fannedReveal
                let pinnedY = past + pinInset + CGFloat(index) * collapsedReveal
                Button {
                    onCardTap(item)
                } label: {
                    TokenCardView(data: item, height: cardHeight)
                }
                .buttonStyle(.plain)
                .offset(y: max(fannedY, pinnedY))
                // Cards drawn front-to-back so the last (highest-value) sits on top.
                .zIndex(Double(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: stackHeight, alignment: .top)
    }
}
