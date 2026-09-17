//
//  LinkCashCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore
import Kingfisher

/// The cash-link card that sits above a message's text, inside the same bubble. Dumb — everything
/// it draws arrives already formatted on `LinkCard.Cash`, the same way `ChatCashCardCell` takes its
/// strings off `ChatCashContent`.
///
/// It draws nothing tappable of its own. Opening the link is the bubble's job, through the same
/// deep-link path a tap on the URL in the text takes, so there is exactly one way in.
final class LinkCashCardView: UIView {

    /// The type row's brand mark, shown before the token is known.
    private static let brand = "Cash Link"

    private let coinIcon = UIImageView()
    private let tokenLabel = UILabel()
    private let amountLabel = UILabel()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        // A tint over the bubble rather than its own fill: the card is inside the bubble, and a
        // second opaque ground there reads as a bubble within a bubble.
        backgroundColor = UIColor.white.withAlphaComponent(0.12)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        coinIcon.contentMode = .scaleAspectFill
        coinIcon.clipsToBounds = true
        coinIcon.layer.cornerRadius = 6.5
        coinIcon.translatesAutoresizingMaskIntoConstraints = false

        tokenLabel.font = .default(size: 12, weight: .bold)
        tokenLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        let tokenRow = UIStackView(arrangedSubviews: [coinIcon, tokenLabel])
        tokenRow.spacing = 4
        tokenRow.alignment = .center

        amountLabel.font = .default(size: 28, weight: .bold)
        amountLabel.textColor = .white
        amountLabel.numberOfLines = 1
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5

        captionLabel.font = .default(size: 12, weight: .bold)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        let stack = UIStackView(arrangedSubviews: [tokenRow, amountLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            coinIcon.widthAnchor.constraint(equalToConstant: 13),
            coinIcon.heightAnchor.constraint(equalToConstant: 13),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    func prepareForReuse() {
        coinIcon.kf.cancelDownloadTask()
        coinIcon.image = nil
    }

    /// Draws `card`. An unresolved card — including one whose lookup failed, timed out or never ran
    /// — is the branded shell with no amount and no caption, which is the floor the resolved card
    /// degrades to rather than an error state.
    func configure(with card: LinkCard) {
        switch card {
        case .cash(let cash):
            switch cash.state {
            case .unresolved:
                tokenLabel.text = Self.brand
                amountLabel.isHidden = true
                captionLabel.isHidden = true
                coinIcon.isHidden = true
                coinIcon.kf.cancelDownloadTask()
                coinIcon.image = nil

            case .resolved(let value):
                tokenLabel.text = value.tokenSymbol
                amountLabel.text = value.amount
                amountLabel.isHidden = false
                captionLabel.text = value.caption
                captionLabel.isHidden = false
                coinIcon.isHidden = value.iconURL == nil
                coinIcon.kf.setImage(with: value.iconURL)
            }
        }
    }
}
#endif
