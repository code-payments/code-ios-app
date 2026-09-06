//
//  ChatQuotePanelView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

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

    /// The panel's own inset from the bubble's edges — the body's leading inset, so the quote's
    /// rule and the text below it share one margin.
    static let horizontalInset: CGFloat = 12
    /// Gap between the panel and the body beneath it.
    static let bottomSpacing: CGFloat = 6

    /// Sized to the cap height of the amount beside it, so the flag reads as a mark on the line
    /// rather than as a second element the line has to make room for.
    private static let flagDiameter: CGFloat = 14

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
        layer.cornerRadius = 8
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

        NSLayoutConstraint.activate([
            // Flush against the cell's leading edge and the full height of it, so the cell reads as
            // a quote rather than a card with a line drawn near it. The corner radius clips it.
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.widthAnchor.constraint(equalToConstant: 3),

            authorLabel.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 8),
            authorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            authorLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            detailRow.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            detailRow.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
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

    func configure(with quote: ChatQuote) {
        targetStableID = quote.stableID
        // The author's own colour, derived from their user id — the same colour the composer's strip
        // draws them in, and the same one Android does. An original with no known author falls back
        // to the neutral secondary, which is what `ComplementaryPalette` returns for a nil id.
        let ruleColor = ComplementaryPalette.uiColor(.start, for: quote.authorID)
        rule.backgroundColor = ruleColor
        authorLabel.textColor = ComplementaryPalette.uiColor(.middle, for: quote.authorID)
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
        case .text, .unavailable:
            flagView.isHidden = true
            tokenLabel.isHidden = true
            snippetLabel.textColor = Self.snippetColor
        }
        let spoken = switch quote.kind {
        case .cash(let token, _):  "\(quote.snippet) \(token)"
        case .text, .unavailable:  quote.snippet
        }
        isUserInteractionEnabled = quote.isJumpable
        accessibilityLabel = quote.authorName.isEmpty
            ? spoken
            : "Replying to \(quote.authorName): \(spoken)"
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
