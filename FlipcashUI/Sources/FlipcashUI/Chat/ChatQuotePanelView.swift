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
/// and one or two lines of the original. Tapping it asks to jump to that message — but only when
/// there is a row to jump to, which `ChatQuote.isJumpable` decides.
final class ChatQuotePanelView: UIView {

    /// Called with the target row's stable id when the panel is tapped. Silent for a quote that
    /// cannot be jumped to.
    var onTap: ((String) -> Void)?

    private var targetStableID: String?

    private let rule = UIView()
    private let authorLabel = UILabel()
    private let snippetLabel = UILabel()

    /// The panel's own inset from the bubble's edges — the body's leading inset, so the quote's
    /// rule and the text below it share one margin.
    static let horizontalInset: CGFloat = 12
    /// Gap between the panel and the body beneath it.
    static let bottomSpacing: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true

        rule.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        rule.layer.cornerRadius = 1
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        authorLabel.font = .default(size: 12, weight: .bold)
        authorLabel.textColor = .white
        authorLabel.numberOfLines = 1
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(authorLabel)

        snippetLabel.font = .default(size: 12, weight: .medium)
        snippetLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        // One line in the bubble, per the spec: the panel is a citation, not a second message, and
        // a two-line panel over a one-line reply reads as the wrong thing being the point. The
        // composer's strip allows two, because there the quote *is* the subject.
        snippetLabel.numberOfLines = 1
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(snippetLabel)

        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rule.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            rule.widthAnchor.constraint(equalToConstant: 2),

            authorLabel.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 8),
            authorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            authorLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),

            snippetLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 1),
            snippetLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "chat-quote-panel"
    }

    func configure(with quote: ChatQuote) {
        targetStableID = quote.stableID
        // An unavailable original has no author to name, so the author line collapses rather than
        // rendering an empty run.
        authorLabel.text = quote.authorName
        authorLabel.isHidden = quote.authorName.isEmpty
        snippetLabel.text = quote.snippet
        isUserInteractionEnabled = quote.isJumpable
        accessibilityLabel = quote.authorName.isEmpty
            ? quote.snippet
            : "Replying to \(quote.authorName): \(quote.snippet)"
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
