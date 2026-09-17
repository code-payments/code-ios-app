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

/// The cash-link card: a paper ticket drawn in place of the URL it was made from.
///
/// Two pieces stacked — the ticket and its stub — with a scored seam between them and a notch
/// bitten out of each side. The notches are *cleared* rather than painted, so the transcript shows
/// through them and the card reads as perforated paper instead of one panel with a line across it.
///
/// A claimed link is drawn with the stub simply not there: no gap and no offset, because the
/// half-notches left along the ticket's bottom edge are the evidence. The band the stub occupied
/// stays open at its full height in every state, so a lookup landing never changes the card's
/// height and shoves the transcript.
///
/// Paper and ink are fixed for every cash link regardless of mint. Painting the token's own bill
/// would need colours the lookup may not have, and a card in the fallback green under a name we do
/// not hold would brand the link as a token it may not pay out.
///
/// Drawn in UIKit rather than by hosting SwiftUI, because this sits inside a recycled transcript
/// bubble and hosting a SwiftUI view per dequeue costs a view-controller adoption —
/// `ChatAuthorAvatarView` makes the same trade for the same reason.
///
/// Dumb — everything it draws arrives already formatted on `LinkCard.Cash`, the same way
/// `ChatCashCardCell` takes its strings off `ChatCashContent`. Opening the link is the bubble's
/// job, through the same deep-link path the URL took, so there is exactly one way in.
final class LinkCashCardView: UIView {

    /// The type row's brand mark, shown when there is no token to name.
    private static let brand = "Cash Link"

    /// The proportions of the wallet's bill: 224pt of card across 328pt of usable width — its own
    /// height at full width less two screen insets on a 375pt phone. A chat bubble is a good deal
    /// narrower than that, and scaling the height with the width is what keeps the card a ticket
    /// there rather than a tall panel.
    private static let aspectRatio: CGFloat = 224.0 / 328.0

    /// The stub's share of the card's height, held whether or not the stub is drawn.
    private static let stubShare: CGFloat = 0.28

    private static let notchRadius: CGFloat = 9
    private static let dash: [NSNumber] = [4, 4]
    private static let inset: CGFloat = 14
    private static let iconSize: CGFloat = 20
    private static let pillHeight: CGFloat = 26

    private static let paper = UIColor(red: 242 / 255, green: 240 / 255, blue: 234 / 255, alpha: 1)
    private static let ink = UIColor(red: 20 / 255, green: 18 / 255, blue: 31 / 255, alpha: 1)

    private let topPiece = UIView()
    private let stubPiece = UIView()
    private let topMask = CAShapeLayer()
    private let stubMask = CAShapeLayer()
    private let score = CAShapeLayer()
    private let silhouette = CAShapeLayer()
    private let topDim = UIView()
    private let stubDim = UIView()

    private let coinIcon = UIImageView()
    private let tokenLabel = UILabel()
    private let amountLabel = UILabel()
    private let stubPill = UIView()
    private let stubLabel = UILabel()
    private let tornLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        topPiece.backgroundColor = Self.paper
        topPiece.layer.mask = topMask
        addSubview(topPiece)

        stubPiece.backgroundColor = Self.paper
        stubPiece.layer.mask = stubMask
        addSubview(stubPiece)

        // The score belongs to the ticket rather than sitting between the two pieces: on the
        // ticket's layer it is clipped by the ticket's own mask and covered by the ticket's dim,
        // so it cannot outlive the paper it is scored into.
        score.strokeColor = Self.ink.withAlphaComponent(0.45).cgColor
        score.lineWidth = 1
        score.lineDashPattern = Self.dash
        score.fillColor = nil
        topPiece.layer.addSublayer(score)

        coinIcon.contentMode = .scaleAspectFill
        coinIcon.clipsToBounds = true
        coinIcon.layer.cornerRadius = Self.iconSize / 2
        topPiece.addSubview(coinIcon)

        tokenLabel.font = .appTextSmall
        tokenLabel.textColor = Self.ink.withAlphaComponent(0.55)
        tokenLabel.numberOfLines = 1
        topPiece.addSubview(tokenLabel)

        amountLabel.font = .appDisplaySmall
        amountLabel.textColor = Self.ink
        amountLabel.numberOfLines = 1
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5
        topPiece.addSubview(amountLabel)

        stubPill.backgroundColor = Self.ink
        stubPiece.addSubview(stubPill)

        stubLabel.font = .appTextSmall
        stubLabel.numberOfLines = 1
        stubLabel.textAlignment = .center
        stubPiece.addSubview(stubLabel)

        // Each piece dims itself, added last so the piece's mask clips it. One overlay across the
        // whole card would paint over the cleared notches and fill the holes back in.
        for (dim, piece) in [(topDim, topPiece), (stubDim, stubPiece)] {
            dim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            dim.isUserInteractionEnabled = false
            piece.addSubview(dim)
        }

        // The torn state's furniture hangs off `self`, because what it stands in for is the piece
        // that is gone. The silhouette traces the stub's outline, notch bites included: a line
        // struck straight across the band would close the bite that is the whole tell.
        silhouette.strokeColor = Self.paper.withAlphaComponent(0.25).cgColor
        silhouette.lineWidth = 1
        silhouette.lineDashPattern = Self.dash
        silhouette.fillColor = nil
        layer.addSublayer(silhouette)

        // Off-paper, and so outside either dim: the paper this would have sat on left with whoever
        // claimed the link.
        tornLabel.font = .appTextSmall
        tornLabel.textColor = UIColor(Color.textSecondary)
        tornLabel.textAlignment = .center
        tornLabel.numberOfLines = 1
        addSubview(tornLabel)

        NSLayoutConstraint.activate([
            // The ticket's proportions, not its size. Always live, including while collapsed: a
            // card with no width has no height either, so this stays consistent with the bubble's
            // zero-size constraints rather than fighting them.
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: Self.aspectRatio),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        let notch = Self.notchRadius
        let corner = Metrics.boxRadius
        let stubHeight = (height * Self.stubShare).rounded()
        let seam = height - stubHeight

        topPiece.frame = CGRect(x: 0, y: 0, width: width, height: seam)
        stubPiece.frame = CGRect(x: 0, y: seam, width: width, height: stubHeight)
        topDim.frame = topPiece.bounds
        stubDim.frame = stubPiece.bounds

        topMask.frame = topPiece.bounds
        topMask.path = Self.ticketPath(size: topPiece.bounds.size, notch: notch, corner: corner).cgPath
        stubMask.frame = stubPiece.bounds
        stubMask.path = Self.stubPath(size: stubPiece.bounds.size, notch: notch, corner: corner).cgPath

        // Between the notches, and half a point up so the hairline lands inside the paper rather
        // than straddling its bottom edge.
        let line = UIBezierPath()
        line.move(to: CGPoint(x: notch, y: seam - 0.5))
        line.addLine(to: CGPoint(x: width - notch, y: seam - 0.5))
        score.frame = topPiece.bounds
        score.path = line.cgPath

        silhouette.frame = stubPiece.frame
        silhouette.path = stubMask.path

        layOutHeader(in: topPiece.bounds)
        layOutStub(in: stubPiece.bounds)
        tornLabel.frame = stubPiece.frame
    }

    /// Icon and token name centred as one group along the top, amount centred in what is left.
    private func layOutHeader(in bounds: CGRect) {
        let inset = Self.inset
        let available = bounds.width - inset * 2
        let lead = coinIcon.isHidden ? 0 : Self.iconSize + 6

        let nameSize = tokenLabel.sizeThatFits(CGSize(width: available - lead, height: .greatestFiniteMagnitude))
        let nameWidth = min(nameSize.width, available - lead)
        let rowHeight = max(Self.iconSize, nameSize.height)
        let rowX = ((bounds.width - (nameWidth + lead)) / 2).rounded()

        coinIcon.frame = CGRect(
            x: rowX,
            y: inset + ((rowHeight - Self.iconSize) / 2).rounded(),
            width: Self.iconSize,
            height: Self.iconSize
        )
        tokenLabel.frame = CGRect(x: rowX + lead, y: inset, width: nameWidth, height: rowHeight)

        let amountTop = inset + rowHeight
        amountLabel.frame = CGRect(
            x: inset,
            y: amountTop,
            width: available,
            height: max(0, bounds.height - amountTop - inset)
        )
    }

    private func layOutStub(in bounds: CGRect) {
        let available = bounds.width - Self.inset * 2
        let textSize = stubLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        let pilled = !stubPill.isHidden
        let boxHeight = pilled ? Self.pillHeight : textSize.height
        let boxWidth = min(available, textSize.width + (pilled ? 24 : 0))

        stubLabel.frame = CGRect(
            x: ((bounds.width - boxWidth) / 2).rounded(),
            y: ((bounds.height - boxHeight) / 2).rounded(),
            width: boxWidth,
            height: boxHeight
        )
        stubPill.frame = stubLabel.frame
        stubPill.layer.cornerRadius = boxHeight / 2
    }

    func prepareForReuse() {
        coinIcon.kf.cancelDownloadTask()
        coinIcon.image = nil
    }

    /// Draws `card`. An unresolved card — including one whose lookup failed, timed out or never ran
    /// — is the identical ticket carrying the brand mark, with no icon and no amount. Nothing moves
    /// or resizes when the lookup lands; text appears. A second drawing for the unresolved case
    /// would be a second thing that can look wrong.
    func configure(with card: LinkCard) {
        switch card {
        case .cash(let cash):
            switch cash.state {
            case .unresolved:
                tokenLabel.text = Self.brand
                coinIcon.isHidden = true
                coinIcon.kf.cancelDownloadTask()
                coinIcon.image = nil
                amountLabel.text = nil
                stubPill.isHidden = true
                stubLabel.text = nil
                tornLabel.text = nil
                setTorn(false, dimmed: false)

            case .resolved(let value):
                tokenLabel.text = value.tokenName
                coinIcon.isHidden = value.iconURL == nil
                coinIcon.kf.setImage(with: value.iconURL)
                amountLabel.text = value.amount

                // The pill is the card's one call to action, drawn only while there is something
                // to do. A claimed or expired link reads as a note instead.
                let actionable = value.claim == .claimable
                stubPill.isHidden = !actionable
                stubLabel.textColor = actionable ? Self.paper : Self.ink.withAlphaComponent(0.55)
                stubLabel.text = value.claim == .claimed ? nil : value.caption
                tornLabel.text = value.caption
                setTorn(value.claim == .claimed, dimmed: value.claim != .claimable)
            }
        }
        setNeedsLayout()
    }

    /// Claimed tears: the stub is not drawn and its silhouette holds the band. Expired dims but
    /// stays intact — expired means the link lapsed where it sat, not that anyone took it.
    private func setTorn(_ torn: Bool, dimmed: Bool) {
        stubPiece.isHidden = torn
        score.isHidden = torn
        silhouette.isHidden = !torn
        tornLabel.isHidden = !torn
        topDim.isHidden = !dimmed
        stubDim.isHidden = !dimmed
    }

    // MARK: - The two halves of the perforation

    /// The ticket: rounded across the top, square at the seam, with a half-notch bitten inward from
    /// each bottom corner. Traced as one closed outline rather than punched with an even-odd rule,
    /// because the stub's identical outline is also stroked as the torn state's silhouette.
    private static func ticketPath(size: CGSize, notch: CGFloat, corner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let width = size.width
        let height = size.height
        path.move(to: CGPoint(x: 0, y: corner))
        path.addArc(withCenter: CGPoint(x: corner, y: corner), radius: corner,
                    startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: width - corner, y: 0))
        path.addArc(withCenter: CGPoint(x: width - corner, y: corner), radius: corner,
                    startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: width, y: height - notch))
        path.addArc(withCenter: CGPoint(x: width, y: height), radius: notch,
                    startAngle: 1.5 * .pi, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: notch, y: height))
        path.addArc(withCenter: CGPoint(x: 0, y: height), radius: notch,
                    startAngle: 0, endAngle: 1.5 * .pi, clockwise: false)
        path.close()
        return path
    }

    /// The stub: the ticket inverted — square at the seam with the matching half-notches along its
    /// top, rounded across the bottom. The two halves of each notch meet to make one hole.
    private static func stubPath(size: CGSize, notch: CGFloat, corner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let width = size.width
        let height = size.height
        path.move(to: CGPoint(x: 0, y: notch))
        path.addArc(withCenter: .zero, radius: notch,
                    startAngle: 0.5 * .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: width - notch, y: 0))
        path.addArc(withCenter: CGPoint(x: width, y: 0), radius: notch,
                    startAngle: .pi, endAngle: 0.5 * .pi, clockwise: false)
        path.addLine(to: CGPoint(x: width, y: height - corner))
        path.addArc(withCenter: CGPoint(x: width - corner, y: height - corner), radius: corner,
                    startAngle: 0, endAngle: 0.5 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: corner, y: height))
        path.addArc(withCenter: CGPoint(x: corner, y: height - corner), radius: corner,
                    startAngle: 0.5 * .pi, endAngle: .pi, clockwise: true)
        path.close()
        return path
    }
}
#endif
