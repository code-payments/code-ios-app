//
//  LinkableBubbleView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A chat bubble that renders text with tappable links, over the shared `BubbleBackgroundView`. Used
/// only for messages that contain a link; plain text stays on the cheaper `ChatBubbleView` (a
/// `UILabel`). Link taps are reported through `onOpenURL`; the bubble itself opens nothing.
public final class LinkableBubbleView: UIView {

    private let background = BubbleBackgroundView()
    private let textView = LinkTextView()
    private let editedLabel = EditedMarker.makeLabel()
    private let cardView = LinkCashCardView()

    /// Called when the user taps a detected link.
    var onOpenURL: ((URL) -> Void)?

    private(set) var quotePanel = ChatQuotePanelView()

    /// Forwarded from the panel: the stable id of the message to jump to.
    var onQuoteTap: ((String) -> Void)? {
        get { quotePanel.onTap }
        set { quotePanel.onTap = newValue }
    }

    /// Body pinned to the bubble's top, for a message with no quote.
    private var textTopToBubble: NSLayoutConstraint!
    /// Body pinned below the quote panel, for a reply.
    private var textTopToQuote: NSLayoutConstraint!
    /// Body pinned below the link card, for a message that carries one. The card takes whichever
    /// top the body would otherwise have had, so a reply with a card still reads quote, card, text.
    private var textTopToCard: NSLayoutConstraint!
    private var cardTopToBubble: NSLayoutConstraint!
    private var cardTopToQuote: NSLayoutConstraint!
    private var cardSides: [NSLayoutConstraint] = []
    /// Collapses the card to nothing in both axes when there is none, for the same reason the quote
    /// panel collapses in both: a card pinned to the bubble's sides would otherwise put a floor
    /// under every link bubble's width.
    private var cardCollapse: [NSLayoutConstraint] = []
    /// Collapses the panel to nothing when there is no quote, in both axes. Height alone is not
    /// enough: the panel is pinned to both of the bubble's sides, so whatever width it demands with
    /// nothing in it — the rule and its gutters — becomes a floor under every bubble's width, and a
    /// one-character message comes out as wide as a two-word one.
    private var quoteCollapse: [NSLayoutConstraint] = []
    /// Stretches the panel to the bubble's trailing edge, and so carries a wide quote's width out to
    /// the bubble. Live only alongside a quote: against a collapsed panel the same equality pulls the
    /// *other* way and squeezes the bubble down onto the panel's zero width.
    private var quoteTrailing: NSLayoutConstraint!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // Deliberately off. `LinkDetector` is the one detector, gated by the cross-platform
        // detection vectors and by the guards those vectors cover — the ASCII-authority check that
        // stops a glued emoji from retargeting a host through Punycode, among them. The text view's
        // own detection is a second detector with none of that, so the spans are applied from
        // `LinkPreview.links` in `configure(with:)` instead.
        textView.dataDetectorTypes = []
        textView.font = .default(size: 16, weight: .medium)
        textView.textColor = .white
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.white,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        addSubview(editedLabel)

        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quotePanel)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        textTopToBubble = textView.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        textTopToQuote = textView.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        quoteCollapse = [
            quotePanel.heightAnchor.constraint(equalToConstant: 0),
            quotePanel.widthAnchor.constraint(equalToConstant: 0),
        ]

        textTopToCard = textView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 8)
        cardTopToBubble = cardView.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        cardTopToQuote = cardView.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        cardSides = [
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ]
        cardCollapse = [
            cardView.heightAnchor.constraint(equalToConstant: 0),
            cardView.widthAnchor.constraint(equalToConstant: 0),
        ]
        // Parks the collapsed card somewhere definite. Its real top and sides are switched off with
        // it, and a zero-sized view with no position left is ambiguous rather than free.
        let cardParkTop = cardView.topAnchor.constraint(equalTo: topAnchor)
        let cardParkLeading = cardView.leadingAnchor.constraint(equalTo: leadingAnchor)
        cardParkTop.priority = .defaultLow
        cardParkLeading.priority = .defaultLow

        quoteTrailing = quotePanel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -ChatQuotePanelView.surroundInset
        )

        NSLayoutConstraint.activate(quoteCollapse + cardCollapse + [
            cardParkTop,
            cardParkLeading,
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),

            quotePanel.topAnchor.constraint(equalTo: topAnchor, constant: ChatQuotePanelView.surroundInset),
            quotePanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatQuotePanelView.surroundInset),
            textTopToBubble,
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Same bottom-trailing corner as the plain bubble, off the same reservation run.
            editedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -EditedMarker.trailingInset),
            editedLabel.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
        ])
    }

    /// The bubble's shape, for clipping the context-menu lift preview.
    var maskingPath: UIBezierPath { background.maskingPath }

    /// Flashes the bubble's ground to point the eye at this message after a jump.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) { background.flashAttention(startedAt: start) }

    /// Whether this bubble is currently flashing.
    var isFlashingAttention: Bool { background.isFlashingAttention }

    func prepareForReuse() {
        textView.resignFirstResponder()
        quotePanel.onTap = nil
        cardView.prepareForReuse()
    }

    public func configure(with message: ChatMessage) {
        // Shares the plain bubble's text builder so a link message gets the same body styling, the
        // same tombstone copy, and the same "Edited" reservation, with the link spans laid over it
        // from the preview the mapper already detected.
        textView.attributedText = Self.linkedText(for: message)
        editedLabel.isHidden = !ChatBubbleView.showsEditedMarker(for: message)

        // Card first, because it decides which top the body gets.
        if let card = message.linkPreview?.card {
            cardView.isHidden = false
            cardView.configure(with: card)
            NSLayoutConstraint.deactivate(cardCollapse)
            NSLayoutConstraint.activate(cardSides)
        } else {
            cardView.isHidden = true
            NSLayoutConstraint.deactivate(cardSides + [cardTopToBubble, cardTopToQuote, textTopToCard])
            NSLayoutConstraint.activate(cardCollapse)
        }

        // Deactivate before activating: with both top constraints live the layout is
        // unsatisfiable, and UIKit resolves that by breaking one at random.
        let hasCard = message.linkPreview?.card != nil
        if let quote = message.quote {
            quotePanel.isHidden = false
            quotePanel.configure(with: quote)
            NSLayoutConstraint.deactivate(quoteCollapse)
            quoteTrailing.isActive = true
            textTopToBubble.isActive = false
            cardTopToBubble.isActive = false
            textTopToQuote.isActive = !hasCard
            cardTopToQuote.isActive = hasCard
            textTopToCard.isActive = hasCard
        } else {
            quotePanel.isHidden = true
            quotePanel.clear()
            textTopToQuote.isActive = false
            cardTopToQuote.isActive = false
            textTopToBubble.isActive = !hasCard
            cardTopToBubble.isActive = hasCard
            textTopToCard.isActive = hasCard
            quoteTrailing.isActive = false
            NSLayoutConstraint.activate(quoteCollapse)
        }

        background.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
            ),
            identity: message.id
        )
    }
}

extension LinkableBubbleView {

    /// The bubble's body with a link attribute over each detected span.
    ///
    /// `DetectedLink.range` is already UTF-16 offsets into the same string `displayText` renders, so
    /// the ranges apply straight to the attributed string. They are clamped anyway: the preview is
    /// derived from the message text at map time, and a row that somehow carries a stale preview
    /// should lose its underline rather than trap.
    static func linkedText(for message: ChatMessage) -> NSAttributedString? {
        guard let text = ChatBubbleView.displayText(for: message) else { return nil }
        guard let links = message.linkPreview?.links, !links.isEmpty else { return text }

        let result = NSMutableAttributedString(attributedString: text)
        for link in links where link.length > 0 {
            guard link.location >= 0, link.location + link.length <= result.length else { continue }
            result.addAttribute(.link, value: link.url, range: link.range)
        }
        return result
    }
}

extension LinkableBubbleView: UITextViewDelegate {
    /// Route the tap to `onOpenURL` instead of the system's Safari open.
    public func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        if case .link(let url) = textItem.content {
            return UIAction { [weak self] _ in self?.onOpenURL?(url) }
        }
        return defaultAction
    }

    /// Suppress the per-link context menu so the cell's long-press "Copy" menu isn't shadowed.
    public func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        nil
    }
}

/// A `UITextView` that shows text and taps links but refuses selection, the loupe, and the edit menu —
/// so the cell's long-press "Copy" context menu and the context-menu lift keep working. Mirrors
/// ChatLayout's own `MessageTextView` recipe.
private final class LinkTextView: UITextView {
    override var isFocused: Bool { false }
    override var canBecomeFirstResponder: Bool { false }
    override var canBecomeFocused: Bool { false }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
#endif
