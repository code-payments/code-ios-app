//
//  LinkCashCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore
import Kingfisher

/// The cash-link card: the same bill the wallet deck and the token screen draw, in place of the
/// URL it was made from. A link to a token is recognisably that token before it is opened.
///
/// Drawn in UIKit rather than by hosting `TokenCardView`, because this sits inside a recycled
/// transcript bubble and hosting a SwiftUI view per dequeue costs a view-controller adoption —
/// `ChatAuthorAvatarView` makes the same trade for the same reason. The palette is not restated:
/// both renderers take their stops from ``TokenBillStyle``.
///
/// Dumb — everything it draws arrives already formatted on `LinkCard.Cash`, the same way
/// `ChatCashCardCell` takes its strings off `ChatCashContent`. It draws nothing tappable of its
/// own: opening the link is the bubble's job, through the same deep-link path the URL took, so
/// there is exactly one way in.
final class LinkCashCardView: UIView {

    /// The type row's brand mark, shown when there is no token to name.
    private static let brand = "Cash Link"

    /// The wallet bill's inset, and the "$" watermark's size on a full-height card. Both scale
    /// with the card, which in a bubble is a fraction of the wallet's width.
    private static let referenceHeight: CGFloat = 224
    private static let referenceInset: CGFloat = 16
    private static let referenceWatermark: CGFloat = 213

    private let gradient = CAGradientLayer()
    private let watermark = UILabel()
    private let coinIcon = UIImageView()
    private let tokenLabel = UILabel()
    private let amountLabel = UILabel()
    private let captionLabel = UILabel()

    /// The watermark's last applied point size, so a layout pass that changes nothing does not
    /// dirty the label and ask for another.
    private var watermarkSize: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        layer.cornerRadius = TokenBillStyle.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradient, at: 0)

        // The reserve bill's oversized "$", tucked toward the trailing edge and taller than the
        // card so it clips top and bottom. Overlay blend rather than plain white, matching the
        // SwiftUI card's watermark (node 9223:23556).
        watermark.text = "$"
        watermark.textColor = .white
        watermark.alpha = 0.30
        watermark.layer.compositingFilter = "overlayBlendMode"
        watermark.isUserInteractionEnabled = false
        watermark.isAccessibilityElement = false
        watermark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(watermark)

        coinIcon.contentMode = .scaleAspectFill
        coinIcon.clipsToBounds = true
        coinIcon.layer.cornerRadius = 12
        coinIcon.translatesAutoresizingMaskIntoConstraints = false

        tokenLabel.font = .appTextSmall
        tokenLabel.textColor = .white
        tokenLabel.numberOfLines = 1

        amountLabel.font = .appDisplaySmall
        amountLabel.textColor = .white
        amountLabel.numberOfLines = 1
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [coinIcon, tokenLabel, UIView(), amountLabel])
        header.spacing = 8
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        captionLabel.font = .appTextSmall
        captionLabel.textColor = .white
        captionLabel.numberOfLines = 1
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)

        // The inset is the wallet card's own, unscaled: the bill's proportions change with the
        // container but its furniture does not, the same way Android's `TokenCard` takes a height
        // and leaves its padding alone.
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: Self.referenceInset),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.referenceInset),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.referenceInset),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.referenceInset),
            captionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.referenceInset),
            coinIcon.widthAnchor.constraint(equalToConstant: 24),
            coinIcon.heightAnchor.constraint(equalToConstant: 24),

            captionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.referenceInset),

            watermark.centerYAnchor.constraint(equalTo: centerYAnchor),
            watermark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            // The bill's proportions, not its size. Always live, including while collapsed: a card
            // with no width has no height either, so this stays consistent with the bubble's
            // zero-size constraints rather than fighting them.
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: TokenBillStyle.aspectRatio),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds

        // The "$" is sized as a proportion of the card, not in points: it is meant to overrun the
        // bill's height and clip, and a fixed 213pt on a bubble-width card would leave a stroke
        // rather than a glyph.
        let size = (Self.referenceWatermark * bounds.height / Self.referenceHeight).rounded()
        if size != watermarkSize, size > 0 {
            watermarkSize = size
            watermark.font = .default(size: size, weight: .bold)
        }
    }

    func prepareForReuse() {
        coinIcon.kf.cancelDownloadTask()
        coinIcon.image = nil
    }

    /// Draws `card`. An unresolved card — including one whose lookup failed, timed out or never ran
    /// — is a neutral panel of the same size carrying the brand mark, which is the floor the bill
    /// degrades to rather than an error state. There is no honest bill for a token whose name and
    /// colours are unknown, so a guess is not offered in place of one.
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
                watermark.isHidden = true
                // No token colour to take yet. A neutral ground, dark enough to separate the card
                // from the bubble it sits on and no darker.
                gradient.colors = Array(repeating: UIColor.white.withAlphaComponent(0.10).cgColor, count: 2)

            case .resolved(let value):
                tokenLabel.text = value.tokenName
                amountLabel.text = value.amount
                amountLabel.isHidden = false
                captionLabel.text = value.caption
                captionLabel.isHidden = false
                coinIcon.isHidden = value.iconURL == nil
                coinIcon.kf.setImage(with: value.iconURL)
                watermark.isHidden = !value.isUSDF
                gradient.colors = TokenBillStyle
                    .colorStops(colors: value.billColors, isUSDF: value.isUSDF)
                    .map { UIColor($0).cgColor }
            }
        }
    }
}
#endif
