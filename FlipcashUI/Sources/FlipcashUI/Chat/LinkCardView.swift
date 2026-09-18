//
//  LinkCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The card slot in a link bubble: one frame, one set of proportions, whichever kind of card the
/// message carries.
///
/// The two kinds are laid out by the same rectangle on purpose. A transcript mixing a cash link and
/// a token link should read as one column of cards rather than two card sizes, and the bubble above
/// it switches on whether there is a card at all — not on which one.
///
/// Both kinds are built once and kept, hidden, rather than swapped in per dequeue: this sits in a
/// recycled row, and a transcript that alternates kinds would otherwise allocate a card per scroll.
final class LinkCardView: UIView {

    /// The proportions of the wallet's bill: 224pt of card across 328pt of usable width — its own
    /// height at full width less two screen insets on a 375pt phone. A chat bubble is a good deal
    /// narrower than that, and scaling the height with the width is what keeps a card a card there
    /// rather than a tall panel.
    private static let aspectRatio: CGFloat = 224.0 / 328.0

    private let cashView = LinkCashCardView()
    private let tokenView = LinkTokenCardView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        for card in [cashView, tokenView] as [UIView] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.isHidden = true
            addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.bottomAnchor.constraint(equalTo: bottomAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            // The card's proportions, not its size. Always live, including while collapsed: a card
            // with no width has no height either, so this stays consistent with the bubble's
            // zero-size constraints rather than fighting them.
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: Self.aspectRatio),
        ])
    }

    func prepareForReuse() {
        cashView.prepareForReuse()
        tokenView.prepareForReuse()
    }

    func configure(with card: LinkCard) {
        switch card {
        case .cash(let cash):
            cashView.isHidden = false
            tokenView.isHidden = true
            cashView.configure(with: cash)

        case .token(let token):
            cashView.isHidden = true
            tokenView.isHidden = false
            tokenView.configure(with: token)
        }
    }
}
#endif
