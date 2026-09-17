//
//  LinkTokenCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore
import Kingfisher

/// The token-link card: the wallet's bill, drawn in place of the URL it was made from.
///
/// It names the currency the link opens and nothing else. The wallet's card carries a balance and
/// an appreciation pill; both are the reader's own position, which belongs to the wallet rather
/// than to a row in someone else's transcript — printed here it would be right for one reader at
/// one moment and go stale in place while the wallet moved on.
///
/// Unresolved, the card is the neutral row panel carrying the mint's abbreviated address. The raw
/// link showed that address, so a blank rectangle would leave the reader with less than the text it
/// replaced. Nothing moves when the lookup lands — the address becomes a name, the paint arrives.
///
/// Drawn in UIKit for the same reason as ``LinkCashCardView``: it lives in a recycled transcript
/// bubble, and the wallet's `TokenCardView` is SwiftUI in the app target besides.
final class LinkTokenCardView: UIView {

    /// Shared with ``LinkCashCardView`` so the two kinds sit at the same scale in one transcript.
    private static let inset: CGFloat = 14
    private static let iconSize: CGFloat = 20

    /// The wallet bill's dark-green ground for a token with no customization of its own.
    private static let fallback = UIColor(Color(hex: "#06450F")!)
    /// Sourced from the model, so the Dollars card here and the wallet's cannot drift.
    private static let reserveColors = MintMetadata.usdf.billColors

    /// The reserve bill's oversized "$", as a share of the card's height — 213 over the wallet
    /// card's own 224, so it clips top and bottom at every width the bubble gives it.
    private static let watermarkShare: CGFloat = 213.0 / 224.0

    private let gradient = CAGradientLayer()
    private let watermark = UILabel()
    private let coinIcon = UIImageView()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        clipsToBounds = true
        layer.cornerRadius = Metrics.boxRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(Color.rowSeparator).cgColor

        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradient, at: 0)

        watermark.text = "$"
        watermark.textColor = .white
        watermark.alpha = 0.30
        // The wallet card's overlay blend, which `UILabel` reaches through its layer.
        watermark.layer.compositingFilter = "overlayBlendMode"
        watermark.isUserInteractionEnabled = false
        watermark.isAccessibilityElement = false
        addSubview(watermark)

        coinIcon.contentMode = .scaleAspectFill
        coinIcon.clipsToBounds = true
        coinIcon.layer.cornerRadius = Self.iconSize / 2
        addSubview(coinIcon)

        nameLabel.font = .appTextSmall
        nameLabel.numberOfLines = 1
        addSubview(nameLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        // The gradient is a plain sublayer rather than the view's backing layer, so it is resized
        // without an implicit animation dragging it a frame behind a recycled row's new bounds.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()

        watermark.font = .default(size: (height * Self.watermarkShare).rounded(), weight: .bold)
        let unbounded = CGFloat.greatestFiniteMagnitude
        let watermarkSize = watermark.sizeThatFits(CGSize(width: unbounded, height: unbounded))
        watermark.frame = CGRect(
            x: width - watermarkSize.width - 10,
            y: ((height - watermarkSize.height) / 2).rounded(),
            width: watermarkSize.width,
            height: watermarkSize.height
        )

        let inset = Self.inset
        let lead = coinIcon.isHidden ? 0 : Self.iconSize + 8
        coinIcon.frame = CGRect(x: inset, y: inset, width: Self.iconSize, height: Self.iconSize)

        let nameHeight = nameLabel.font.lineHeight.rounded(.up)
        nameLabel.frame = CGRect(
            x: inset + lead,
            y: inset + ((Self.iconSize - nameHeight) / 2).rounded(),
            width: max(0, width - inset * 2 - lead),
            height: nameHeight
        )
    }

    func prepareForReuse() {
        coinIcon.kf.cancelDownloadTask()
        coinIcon.image = nil
    }

    /// Draws `token`. An unresolved mint — including one the lookup failed, timed out or never ran
    /// on — is the same card in the neutral row colour, naming the address instead of the token.
    func configure(with token: LinkCard.Token) {
        switch token.state {
        case .unresolved:
            gradient.colors = [UIColor(Color.backgroundRow).cgColor, UIColor(Color.backgroundRow).cgColor]
            watermark.isHidden = true
            coinIcon.isHidden = true
            coinIcon.kf.cancelDownloadTask()
            coinIcon.image = nil
            nameLabel.textColor = UIColor(Color.textSecondary)
            nameLabel.text = token.abbreviatedMint

        case .resolved(let value):
            let palette = value.isReserve ? Self.reserveColors : value.colors
            gradient.colors = Self.stops(from: palette)
            watermark.isHidden = !value.isReserve
            coinIcon.isHidden = value.iconURL == nil
            coinIcon.kf.setImage(with: value.iconURL)
            nameLabel.textColor = .white
            nameLabel.text = value.name
        }
        setNeedsLayout()
    }

    /// A gradient needs two ends. One colour is doubled rather than blended toward anything, and no
    /// colour at all falls back to the flat dark green the wallet uses for an uncustomized token.
    private static func stops(from colors: [String]) -> [CGColor] {
        let parsed = colors.compactMap { Color(hex: $0) }.map { UIColor($0).cgColor }
        switch parsed.count {
        case 0:  return [fallback.cgColor, fallback.cgColor]
        case 1:  return [parsed[0], parsed[0]]
        default: return parsed
        }
    }
}
#endif
