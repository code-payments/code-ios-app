//
//  ChatQuotePanelView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore
import Kingfisher

/// The quoted original drawn inside a reply's bubble, above the body: a leading rule, the author,
/// and up to two lines of the original. Tapping it asks to jump to that message — but only when
/// there is a row to jump to, which `ChatQuote.isJumpable` decides.
final class ChatQuotePanelView: UIView {

    /// Called with the target row's stable id when the panel is tapped. Silent for a quote that
    /// cannot be jumped to.
    var onTap: ((String) -> Void)?

    private var targetStableID: String?

    private let rule = UIView()
    private let authorLabel = UILabel()
    private let snippetLabel = UILabel()
    /// Drawn only for a quoted payment: the currency's flag and the mint's name around the amount,
    /// the same pair the cash card itself leads with. A bare "$5.00" in a quote reads as a number
    /// rather than as the payment it points at.
    private let flagView = UIImageView()
    private let tokenLabel = UILabel()
    private let detailRow = UIStackView()
    /// Takes the slack so the flag, amount and token stay clustered at the leading edge instead of
    /// the amount stretching and pushing the token to the far side of the panel.
    private let detailSpacer = UIView()
    /// Drawn only for a quoted photo the viewer may see: the photo itself at the trailing edge.
    private(set) var thumbnailView = UIImageView()
    /// The text's trailing edge with no thumbnail, and with one; exactly one is active.
    private lazy var textTrailingToEdge = authorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
    private lazy var textTrailingToThumbnail = authorLabel.trailingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -8)
    private lazy var thumbnailConstraints = [
        thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
        thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
        thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
    ]

    /// The gap between the panel and the bubble's edges, the same on the top, leading and trailing
    /// sides — the bubble's own vertical margin. One gap rather than three, so ``cornerRadius``
    /// has a single number to be concentric with.
    static let surroundInset: CGFloat = 9
    /// Gap between the panel and the body beneath it: the surround again, so the quote sits on one
    /// rhythm — equal space over it, under it, and below the body.
    static let bottomSpacing: CGFloat = surroundInset

    /// Concentric with the bubble: an inner corner whose arc is the outer one less the gap between
    /// them keeps that gap constant all the way round the turn. Matching the bubble's radius
    /// outright bulges the panel's corner into the space; a tighter one pinches it.
    private static let cornerRadius = BubbleBackgroundView.baseRadius - surroundInset

    private static let ruleWidth: CGFloat = 3

    /// Sized to the cap height of the amount beside it, so the flag reads as a mark on the line
    /// rather than as a second element the line has to make room for.
    private static let flagDiameter: CGFloat = 14

    /// The two text lines' height, so the thumbnail sits in the panel without growing it.
    private static let thumbnailSide: CGFloat = 34

    /// The preview grey a quoted sentence is drawn in.
    private static let snippetColor = UIColor.white.withAlphaComponent(0.55)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The cell's tint behind the author's colour. Low enough that the name keeps its contrast —
    /// the colour is at full strength in the rule and the name, and this is the ground they sit on.
    private static let cellTint: CGFloat = 0.14

    private func setUp() {
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        authorLabel.font = .appTextHeading
        authorLabel.numberOfLines = 1
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(authorLabel)

        snippetLabel.font = .default(size: 12, weight: .medium)
        snippetLabel.textColor = Self.snippetColor
        // Two, matching the composer's strip: one line truncated most quoted sentences mid-clause,
        // which left the reply pointing at something the reader still had to go and open.
        snippetLabel.numberOfLines = 2
        snippetLabel.lineBreakMode = .byTruncatingTail

        flagView.contentMode = .scaleAspectFill
        flagView.clipsToBounds = true
        flagView.layer.cornerRadius = Self.flagDiameter / 2

        tokenLabel.font = .default(size: 12, weight: .medium)
        tokenLabel.textColor = UIColor.white.withAlphaComponent(0.35)
        tokenLabel.numberOfLines = 1

        detailSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        detailSpacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        detailRow.axis = .horizontal
        detailRow.alignment = .center
        detailRow.spacing = 5
        detailRow.translatesAutoresizingMaskIntoConstraints = false
        detailRow.addArrangedSubview(flagView)
        detailRow.addArrangedSubview(snippetLabel)
        detailRow.addArrangedSubview(tokenLabel)
        detailRow.addArrangedSubview(detailSpacer)
        addSubview(detailRow)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 6
        thumbnailView.layer.cornerCurve = .continuous
        // The ground a photo loads onto, so the slot reads as a photo before any bytes arrive.
        thumbnailView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        thumbnailView.isHidden = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        // The rule, the two gutters around the text and the detail row's spacing add up to a width
        // the panel demands even when it holds nothing, and a bubble with no quote would pay for it:
        // the host pins the panel to both of the bubble's sides, so the panel's floor becomes the
        // bubble's. They sit a step under required so the host's collapse can break them and take
        // the floor to zero — see ``ChatQuotePanelView`` in `ChatBubbleView.setUp()`.
        let horizontal = [
            rule.widthAnchor.constraint(equalToConstant: Self.ruleWidth),
            authorLabel.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 8),
            detailRow.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            detailRow.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
        ]
        for constraint in horizontal + [textTrailingToEdge, textTrailingToThumbnail] + thumbnailConstraints {
            constraint.priority = .required - 1
        }
        textTrailingToEdge.isActive = true

        NSLayoutConstraint.activate(horizontal + [
            // Flush against the cell's leading edge and the full height of it, so the cell reads as
            // a quote rather than a card with a line drawn near it. The corner radius clips it.
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),

            authorLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            detailRow.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 1),
            detailRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            flagView.widthAnchor.constraint(equalToConstant: Self.flagDiameter),
            flagView.heightAnchor.constraint(equalToConstant: Self.flagDiameter),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "chat-quote-panel"
    }

    /// - Parameter thumbnailURL: where a quoted photo's thumbnail loads from, or nil until it resolves.
    func configure(with quote: ChatQuote, thumbnailURL: URL? = nil) {
        targetStableID = quote.stableID
        // The author's own colour, derived from their user id — the same colour the composer's strip
        // draws them in, and the same one Android does. An original with no known author falls back
        // to the neutral secondary, which is what `ComplementaryPalette` returns for a nil id.
        let ruleColor = ComplementaryPalette.uiColor(.start, for: quote.authorID)
        rule.backgroundColor = ruleColor
        authorLabel.textColor = ComplementaryPalette.uiNameColor(for: quote.authorID)
        backgroundColor = ruleColor.withAlphaComponent(Self.cellTint)
        // An unavailable original has no author to name, so the author line collapses rather than
        // rendering an empty run.
        authorLabel.text = quote.authorName
        authorLabel.isHidden = quote.authorName.isEmpty
        snippetLabel.text = quote.snippet
        switch quote.kind {
        case .cash(let token, let flagImageName):
            let flag = flagImageName.flatMap { UIImage(named: $0, in: .module, compatibleWith: nil) }
            flagView.image = flag
            flagView.isHidden = flag == nil
            tokenLabel.text = token
            tokenLabel.isHidden = false
            // A payment's amount is the whole of what was said, so it is read rather than glanced
            // at — a step brighter than the preview grey a quoted sentence gets.
            snippetLabel.textColor = UIColor.white.withAlphaComponent(0.75)
            showThumbnail(blobID: nil, url: nil)
        case .media(let thumbnailBlobID):
            flagView.isHidden = true
            tokenLabel.isHidden = true
            snippetLabel.textColor = Self.snippetColor
            showThumbnail(blobID: thumbnailBlobID, url: thumbnailURL)
        case .text, .unavailable:
            flagView.isHidden = true
            tokenLabel.isHidden = true
            snippetLabel.textColor = Self.snippetColor
            showThumbnail(blobID: nil, url: nil)
        }
        let spoken = switch quote.kind {
        case .cash(let token, _):  "\(quote.snippet) \(token)"
        case .text, .media, .unavailable:  quote.snippet
        }
        isUserInteractionEnabled = quote.isJumpable
        accessibilityLabel = quote.authorName.isEmpty
            ? spoken
            : "Replying to \(quote.authorName): \(spoken)"
    }

    /// Empties the panel for a message that has no quote. Hiding it is not enough: `isHidden` only
    /// skips drawing, and the panel is still pinned to both of the bubble's sides, so a recycled
    /// cell's stale author name and snippet go on demanding their width and the bubble stays as
    /// wide as the reply it used to hold.
    func clear() {
        targetStableID = nil
        authorLabel.text = nil
        snippetLabel.text = nil
        tokenLabel.text = nil
        flagView.image = nil
        flagView.isHidden = true
        tokenLabel.isHidden = true
        showThumbnail(blobID: nil, url: nil)
        isUserInteractionEnabled = false
        accessibilityLabel = nil
    }

    /// Shows the thumbnail slot for a photo with a blob, loading it once `url` resolves; hides and
    /// empties it otherwise. A redacted photo has no blob, so it never reaches the network from here.
    private func showThumbnail(blobID: BlobID?, url: URL?) {
        guard let blobID else {
            thumbnailView.kf.cancelDownloadTask()
            thumbnailView.image = nil
            thumbnailView.isHidden = true
            NSLayoutConstraint.deactivate(thumbnailConstraints + [textTrailingToThumbnail])
            textTrailingToEdge.isActive = true
            return
        }
        thumbnailView.isHidden = false
        textTrailingToEdge.isActive = false
        NSLayoutConstraint.activate(thumbnailConstraints + [textTrailingToThumbnail])
        guard let url else {
            thumbnailView.kf.cancelDownloadTask()
            thumbnailView.image = nil
            return
        }
        let side = Self.thumbnailSide
        thumbnailView.kf.setImage(
            with: ChatMediaImageSource.resource(blobID: blobID, url: url),
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: side, height: side))),
                .scaleFactor(traitCollection.displayScale),
            ]
        )
    }

    @objc private func handleTap() {
        guard let targetStableID else { return }
        onTap?(targetStableID)
    }

    /// Drives the tap path from tests, which cannot deliver a real touch to a detached view.
    func simulateTap() {
        guard isUserInteractionEnabled else { return }
        handleTap()
    }
}
#endif
