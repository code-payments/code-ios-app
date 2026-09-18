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
/// `UILabel`). Link taps are reported through `onOpenURL` and card taps through `onLinkCardTap`;
/// the bubble itself opens nothing.
public final class LinkableBubbleView: UIView {

    private let background = BubbleBackgroundView()
    private let textView = LinkTextView()
    private let editedLabel = EditedMarker.makeLabel()
    private let cardView = LinkCardView()

    /// Called when the user taps a detected link.
    var onOpenURL: ((URL) -> Void)?

    /// Called when the user taps the card standing in for a link. The whole card goes back rather
    /// than its URL, because where a tap should land differs by kind and only the owner knows the
    /// transcript it is landing in.
    var onLinkCardTap: ((LinkCard) -> Void)?

    /// The card this bubble is currently drawing. The card is drawn in place of its URL, so the
    /// body no longer carries a span to tap — without this a link-only message would render
    /// something that goes nowhere.
    private var card: LinkCard?

    private(set) var quotePanel = ChatQuotePanelView()

    /// Whether the row currently draws as the card on its own, with no bubble behind it.
    private var isBare = false

    /// Clips the card to the bubble's shape on a bare row. The card's own corner is the bubble's
    /// base radius, so this shows only where a run flattens an inner corner — without it a card in
    /// the middle of a run would keep its full round while the bubbles above and below it are
    /// nearly square. Off otherwise, where the card sits inside the bubble's padding and never
    /// reaches a corner.
    private let cardMask = CAShapeLayer()

    /// The card's inset from the bubble's edges, and the bubble's own vertical padding.
    private static let bodyInset: CGFloat = 12
    private static let bodyPadding: CGFloat = 9

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
    /// Body pinned to the bubble's bottom. Off on a bare row, where the card closes the bubble and
    /// an empty text view left holding the bottom would still claim a line's worth of height.
    private var textBottom: NSLayoutConstraint!
    /// Card pinned to the bubble's bottom, for a row that is nothing but the card.
    private var cardBottomToBubble: NSLayoutConstraint!
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
        cardView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped)))
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
        cardTopToBubble = cardView.topAnchor.constraint(equalTo: topAnchor, constant: Self.bodyPadding)
        cardTopToQuote = cardView.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        cardBottomToBubble = cardView.bottomAnchor.constraint(equalTo: bottomAnchor)
        cardSides = [
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.bodyInset),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.bodyInset),
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

        textBottom = textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bodyPadding)

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
            textBottom,
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.bodyInset),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.bodyInset),

            // Same bottom-trailing corner as the plain bubble, off the same reservation run.
            editedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -EditedMarker.trailingInset),
            editedLabel.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
        ])
    }

    /// The bubble's shape, for clipping the context-menu lift preview. Still the right shape on a
    /// bare row, unlike the plain bubble's: the card fills the frame the bubble would have had and
    /// rounds to the same radius, so the lift traces the card rather than a bubble that is not drawn.
    var maskingPath: UIBezierPath { background.maskingPath }

    /// Flashes the bubble's ground to point the eye at this message after a jump.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) { background.flashAttention(startedAt: start) }

    /// Hands the tapped card to the owner. The card itself stays inert so there is one way in, not
    /// two.
    @objc func cardTapped() {
        card.map { onLinkCardTap?($0) }
    }

    /// Whether this bubble is currently flashing.
    var isFlashingAttention: Bool { background.isFlashingAttention }

    func prepareForReuse() {
        textView.resignFirstResponder()
        quotePanel.onTap = nil
        card = nil
        cardView.prepareForReuse()
    }

    public func configure(with message: ChatMessage) {
        // Shares the plain bubble's text builder so a link message gets the same body styling, the
        // same tombstone copy, and the same "Edited" reservation, with the link spans laid over it
        // from the preview the mapper already detected — less whatever span the card now draws.
        let body = Self.linkedText(for: message)
        textView.attributedText = body?.text
        editedLabel.isHidden = !ChatBubbleView.showsEditedMarker(for: message)

        // Card first, because it decides which top the body gets.
        if let card = message.linkPreview?.card {
            cardView.isHidden = false
            self.card = card
            cardView.configure(with: card)
            NSLayoutConstraint.deactivate(cardCollapse)
            NSLayoutConstraint.activate(cardSides)
        } else {
            cardView.isHidden = true
            self.card = nil
            NSLayoutConstraint.deactivate(cardSides + [cardTopToBubble, cardTopToQuote, textTopToCard])
            NSLayoutConstraint.activate(cardCollapse)
        }

        // A message that was nothing but the link has no text left under the card, so the gap
        // between them closes. The exception is a message the sender edited: the marker is pinned to
        // the body's bottom and needs the run that reserves its hole.
        let keepsBody = body?.hasBody ?? true
        textTopToCard.constant = keepsBody || !editedLabel.isHidden ? 8 : 0

        // Nothing left to put in a bubble. Asked of the message rather than derived from
        // `keepsBody` here, because the transcript mapper asks the same question of this row's
        // neighbours to break the bubble run — one answer, or a bubble flattens its corner toward
        // chrome that is not drawn.
        setBare(message.rendersAsBareLinkCard)

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
            bare: isBare,
            identity: message.id
        )
    }

    /// Switches the bubble between carrying the card and being it.
    ///
    /// The card runs to the full width and height the bubble would have had: its own inset is
    /// inside its frame, so the bubble's padding here would be a second one — and with no fill to
    /// sit inside, it is drawn outside the card's edge, where it reads as a gap rather than as
    /// padding. The body goes with the bubble, bottom constraint included: an empty text view still
    /// lays out a line, and left holding the bubble's bottom it would leave that line's worth of
    /// dead space under the card.
    private func setBare(_ bare: Bool) {
        guard bare != isBare else { return }
        isBare = bare

        // Deactivate before activating: two bottoms on one bubble is unsatisfiable, and UIKit
        // resolves that by breaking one at random.
        if bare {
            textBottom.isActive = false
            cardBottomToBubble.isActive = true
        } else {
            cardBottomToBubble.isActive = false
            textBottom.isActive = true
        }
        textView.isHidden = bare
        cardTopToBubble.constant = bare ? 0 : Self.bodyPadding
        cardSides[0].constant = bare ? 0 : Self.bodyInset
        cardSides[1].constant = bare ? 0 : -Self.bodyInset
        cardView.layer.mask = bare ? cardMask : nil
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard isBare else { return }
        // Taken from the chrome rather than rebuilt, so the card and the bubble it stands in for
        // can never round differently.
        cardMask.frame = cardView.bounds
        cardMask.path = background.maskingPath.cgPath
    }
}

extension LinkableBubbleView {

    /// The bubble's body: every detected link underlined, and the card's own link cut out.
    ///
    /// `DetectedLink.range` is already UTF-16 offsets into the same string `displayText` renders, so
    /// the ranges apply straight to the attributed string. They are clamped anyway: the preview is
    /// derived from the message text at map time, and a row that somehow carries a stale preview
    /// should lose its underline rather than trap.
    ///
    /// The card is the link, drawn — leaving the URL in the body underneath would say the same
    /// thing twice — so the span it was built from goes with it. `hasBody` reports whether any of
    /// the sender's text survived that cut; a message that was nothing but the link leaves none,
    /// and the bubble draws the card on its own.
    static func linkedText(for message: ChatMessage) -> (text: NSAttributedString, hasBody: Bool)? {
        guard let text = ChatBubbleView.displayText(for: message) else { return nil }

        let result = NSMutableAttributedString(attributedString: text)
        for link in message.linkPreview?.links ?? [] where link.length > 0 {
            guard link.location >= 0, link.location + link.length <= result.length else { continue }
            result.addAttribute(.link, value: link.url, range: link.range)
        }

        guard let card = message.linkPreview?.card, case .text(let body) = message.content else {
            return (result, true)
        }
        let bodyText = body as NSString
        guard let cut = LinkCard.cutRange(for: card.range, in: bodyText) else {
            return (result, true)
        }

        // Deleting from the attributed string rather than the raw text is what keeps the *other*
        // links underlined: their ranges shift with the cut on their own, where re-applying them
        // afterwards would need every offset recomputed.
        result.deleteCharacters(in: cut)
        return (result, cut.length < bodyText.length)
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
