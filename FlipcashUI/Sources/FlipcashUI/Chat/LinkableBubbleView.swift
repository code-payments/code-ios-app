//
//  LinkableBubbleView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// A chat bubble that renders text with tappable links, over the shared `BubbleBackgroundView`, or
/// the link card a message was split around, drawn bare. Used only for messages that contain a link;
/// plain text stays on the cheaper `ChatBubbleView` (a `UILabel`). Link taps are reported through
/// `onOpenURL`, `@handle` taps through `onMentionTap`, and card taps through `onLinkCardTap`; the
/// bubble itself opens nothing.
public final class LinkableBubbleView: UIView {

    private let background = BubbleBackgroundView()
    private let textView = LinkTextView()
    private let editedLabel = EditedMarker.makeLabel()
    private let cardView = LinkCardView()

    /// Called when the user taps a detected link.
    var onOpenURL: ((URL) -> Void)?

    /// Called when the user taps an `@handle`, with the handle it names.
    var onMentionTap: ((Username) -> Void)?

    /// Called when the user taps the card standing in for a link. The whole card goes back rather
    /// than its URL, because where a tap should land differs by kind and only the owner knows the
    /// transcript it is landing in.
    var onLinkCardTap: ((LinkCard) -> Void)?

    /// Where the card in this bubble looks its link up. Set before ``configure(with:)``, because
    /// that is when the card subscribes.
    weak var linkCardSource: (any LinkCardSource)?

    /// Called when the card's height changes after the bubble was configured, as a group card's
    /// does when its lookup lands.
    var onCardHeightChange: (() -> Void)?

    /// The card this row is currently drawing. The card is drawn in place of its URL, so the row
    /// has no text span to tap — without this it would render something that goes nowhere.
    private var card: LinkCard?

    /// The whole-card tap. Off for a group or person card, which handle their own taps.
    private lazy var cardTap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))

    /// The tap on a link or mention span. A plain recognizer rather than the text view's own item
    /// action, which is lost when the transcript's tap lowers the keyboard mid-touch.
    private lazy var spanTap = UITapGestureRecognizer(target: self, action: #selector(spanTapped))

    private(set) var quotePanel = ChatQuotePanelView()

    /// Whether the row currently draws as the card on its own, with no bubble behind it.
    private var isBare = false

    /// The body's inset from the bubble's edges, and the bubble's own vertical padding.
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
    /// Card pinned to the row's top, or below the quote of a reply whose first row is the card.
    private var cardTopToBubble: NSLayoutConstraint!
    private var cardTopToQuote: NSLayoutConstraint!
    private var cardSides: [NSLayoutConstraint] = []
    /// Body pinned to the bubble's bottom. Off on a card row, where the card closes the row and an
    /// empty text view left holding the bottom would still claim a line's worth of height.
    private var textBottom: NSLayoutConstraint!
    /// Card pinned to the row's bottom, for a card row.
    private var cardBottomToBubble: NSLayoutConstraint!
    /// Collapses the card to nothing in both axes on a text row, for the same reason the quote
    /// panel collapses in both: a card pinned to the bubble's sides would otherwise put a floor
    /// under every link bubble's width.
    private var cardCollapse: [NSLayoutConstraint] = []
    /// Collapses the panel to nothing when there is no quote, in both axes. Height alone is not
    /// enough: the panel is pinned to both of the bubble's sides, so whatever width it demands with
    /// nothing in it — the rule and its gutters — becomes a floor under every bubble's width, and a
    /// one-character message comes out as wide as a two-word one.
    private var quoteCollapse: [NSLayoutConstraint] = []
    /// The panel's inset from the bubble's top and leading edge. Zero on a card row, which has no
    /// bubble for the panel to sit inside.
    private var quoteTop: NSLayoutConstraint!
    private var quoteLeading: NSLayoutConstraint!
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
        textView.linkTextAttributes = Self.linkAttributes
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        spanTap.delegate = self
        textView.addGestureRecognizer(spanTap)
        addSubview(textView)

        addSubview(editedLabel)

        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quotePanel)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addGestureRecognizer(cardTap)
        cardView.onCardButton = { [weak self] in self?.cardTapped() }
        cardView.onHeightChange = { [weak self] in self?.onCardHeightChange?() }
        addSubview(cardView)

        textTopToBubble = textView.topAnchor.constraint(equalTo: topAnchor, constant: Self.bodyPadding)
        textTopToQuote = textView.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        quoteCollapse = [
            quotePanel.heightAnchor.constraint(equalToConstant: 0),
            quotePanel.widthAnchor.constraint(equalToConstant: 0),
        ]

        cardTopToBubble = cardView.topAnchor.constraint(equalTo: topAnchor)
        cardTopToQuote = cardView.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        cardBottomToBubble = cardView.bottomAnchor.constraint(equalTo: bottomAnchor)
        cardSides = [
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
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

        quoteTop = quotePanel.topAnchor.constraint(equalTo: topAnchor, constant: ChatQuotePanelView.surroundInset)
        quoteLeading = quotePanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatQuotePanelView.surroundInset)
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

            quoteTop,
            quoteLeading,
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
    /// card row: the card fills the frame the bubble would have had and rounds to the same radius,
    /// so the lift traces the card rather than a bubble that is not drawn.
    var maskingPath: UIBezierPath { background.maskingPath }

    /// The outline the row's card is cut to; the standalone radii on a row with no card.
    var cardCornerRadii: RectangleCornerRadii { cardView.cornerRadii }

    /// Flashes the bubble's ground to point the eye at this message after a jump.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) { background.flashAttention(startedAt: start) }

    /// Hands the tapped card to the owner. A cash or token card is inert and the whole card is the
    /// tap target; a group card takes taps only on its button and a person card is its own button,
    /// and both land here too.
    @objc func cardTapped() {
        card.map { onLinkCardTap?($0) }
    }

    /// Hands a tapped link or mention to its callback. Taps off every span fall through to nothing.
    @objc private func spanTapped(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: textView)
        guard let character = textView.characterRange(at: point),
              textView.firstRect(for: character).insetBy(dx: -Self.spanTapSlop, dy: -Self.spanTapSlop).contains(point),
              let text = textView.attributedText
        else { return }
        let index = textView.offset(from: textView.beginningOfDocument, to: character.start)
        switch Self.span(in: text, at: index) {
        case .url(let url): onOpenURL?(url)
        case .mention(let username): onMentionTap?(username)
        case nil: break
        }
    }

    /// How far outside a character's box a tap still lands on it.
    private static let spanTapSlop: CGFloat = 4

    /// Whether this bubble is currently flashing.
    var isFlashingAttention: Bool { background.isFlashingAttention }

    func prepareForReuse() {
        textView.resignFirstResponder()
        quotePanel.onTap = nil
        card = nil
        cardView.prepareForReuse()
    }

    /// Fills the bubble; `quoteThumbnailURL` is where a quoted photo's thumbnail loads from.
    public func configure(with message: ChatMessage, quoteThumbnailURL: URL? = nil) {
        // Shares the plain bubble's text builder so a link message gets the same body styling, the
        // same tombstone copy, and the same "Edited" reservation, with the link spans laid over it
        // from the preview the mapper already detected.
        // The transcript gives a carded link a row of its own, so a row carries either text or the
        // card — never both.
        let bare = message.rendersAsBareLinkCard
        // Empty on a card row: the hidden text still widens the row, and a person card, which gives
        // its own width, would sit short of the column's edge inside it.
        textView.attributedText = bare ? nil : Self.linkedText(for: message)
        setBare(bare)
        // One set of radii for the card and the chrome: a card sits in its bubble run exactly where
        // a text bubble would, with the same corners flattened toward its neighbours.
        let radii = BubbleBackgroundView.radii(
            isFromSelf: message.sender == .me,
            groupedAbove: message.joinsBubbleAbove,
            groupedBelow: message.joinsBubbleBelow
        )
        // A card row's "Edited" marker sits on the column's metadata line instead — see
        // `ChatLinkMessageCell`.
        editedLabel.isHidden = bare || !ChatBubbleView.showsEditedMarker(for: message)

        if bare, let card = message.linkPreview?.card {
            cardView.isHidden = false
            self.card = card
            cardTap.isEnabled = switch card {
            case .group, .user: false
            case .cash, .token: true
            }
            cardView.cornerRadii = radii
            cardView.configure(with: card, source: linkCardSource)
            NSLayoutConstraint.deactivate(cardCollapse)
            NSLayoutConstraint.activate(cardSides)
        } else {
            cardView.isHidden = true
            self.card = nil
            // Drops the last card's subscription and any group card's hold on the slot's height,
            // which would fight the collapse below.
            cardView.prepareForReuse()
            NSLayoutConstraint.deactivate(cardSides)
            NSLayoutConstraint.activate(cardCollapse)
        }

        // Deactivate before activating: with two top constraints live the layout is unsatisfiable,
        // and UIKit resolves that by breaking one at random.
        if let quote = message.quote {
            quotePanel.isHidden = false
            quotePanel.configure(with: quote, thumbnailURL: quoteThumbnailURL)
            NSLayoutConstraint.deactivate(quoteCollapse + [textTopToBubble, cardTopToBubble])
            quoteTrailing.isActive = true
            textTopToQuote.isActive = !bare
            cardTopToQuote.isActive = bare
        } else {
            quotePanel.isHidden = true
            quotePanel.clear()
            NSLayoutConstraint.deactivate([textTopToQuote, cardTopToQuote, quoteTrailing])
            textTopToBubble.isActive = !bare
            cardTopToBubble.isActive = bare
            NSLayoutConstraint.activate(quoteCollapse)
        }

        background.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: radii,
            bare: bare,
            identity: message.id
        )
    }

    /// Switches the row between a text bubble and the card on its own.
    ///
    /// The card runs to the full width and height the bubble would have had: its own inset is
    /// inside its frame, so the bubble's padding here would be a second one — and with no fill to
    /// sit inside, it is drawn outside the card's edge, where it reads as a gap rather than as
    /// padding. A reply's quote stands directly above the card for the same reason. The body goes,
    /// bottom constraint included: an empty text view still lays out a line, and left holding the
    /// row's bottom it would leave that line's worth of dead space under the card.
    private func setBare(_ bare: Bool) {
        guard bare != isBare else { return }
        isBare = bare

        // Deactivate before activating: two bottoms on one row is unsatisfiable, and UIKit resolves
        // that by breaking one at random.
        if bare {
            textBottom.isActive = false
            cardBottomToBubble.isActive = true
        } else {
            cardBottomToBubble.isActive = false
            textBottom.isActive = true
        }
        textView.isHidden = bare
        let quoteInset = bare ? 0 : ChatQuotePanelView.surroundInset
        quoteTop.constant = quoteInset
        quoteLeading.constant = quoteInset
        quoteTrailing.constant = -quoteInset
        setNeedsLayout()
    }
}

extension LinkableBubbleView {

    /// How a link reads in a bubble.
    static let linkAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: UIColor.white,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]

    /// The bubble's body with every detected link underlined and every mention tagged for its pill.
    ///
    /// `DetectedLink.range` is already UTF-16 offsets into the same string `displayText` renders, so
    /// the ranges apply straight to the attributed string. They are clamped anyway: the preview is
    /// derived from the message text at map time, and a row that somehow carries a stale preview
    /// should lose its styling rather than trap.
    static func linkedText(for message: ChatMessage) -> NSAttributedString? {
        guard let text = ChatBubbleView.displayText(for: message) else { return nil }

        let result = NSMutableAttributedString(attributedString: text)
        for link in message.linkPreview?.links ?? [] where link.length > 0 {
            guard link.location >= 0, link.location + link.length <= result.length else { continue }
            result.addAttribute(.link, value: link.url, range: link.range)
        }
        for mention in message.linkPreview?.mentions ?? [] where mention.length > 0 {
            guard mention.location >= 0, mention.location + mention.length <= result.length else { continue }
            result.addAttribute(.textItemTag, value: mention.username.value, range: mention.range)
            // Widens the space on both sides, so the pill grows into room the text gave up rather
            // than over the neighbouring words.
            if mention.location > 0 {
                result.addAttribute(.kern, value: MentionPill.spacing, range: NSRange(location: mention.location - 1, length: 1))
            }
            result.addAttribute(.kern, value: MentionPill.spacing, range: NSRange(location: mention.location + mention.length - 1, length: 1))
        }
        return result
    }
}

extension LinkableBubbleView {

    /// What a tap on the bubble's text lands on.
    enum Span: Equatable {
        case url(URL)
        case mention(Username)
    }

    /// The link or mention covering the UTF-16 offset `index` of `text`, if any.
    static func span(in text: NSAttributedString, at index: Int) -> Span? {
        guard index >= 0, index < text.length else { return nil }
        let attributes = text.attributes(at: index, effectiveRange: nil)
        if let url = attributes[.link] as? URL { return .url(url) }
        if let tag = attributes[.textItemTag] as? String, let username = Username(tag) { return .mention(username) }
        return nil
    }
}

extension LinkableBubbleView: UIGestureRecognizerDelegate {
    /// The span tap runs beside the transcript's keyboard-lowering tap, so one tap does both. It
    /// never runs beside a long press, so lifting the bubble doesn't also open the link.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        !(otherGestureRecognizer is UILongPressGestureRecognizer)
    }
}

extension LinkableBubbleView: UITextViewDelegate {
    /// Route a link to `onOpenURL` instead of the system's Safari open, and a mention to
    /// `onMentionTap`.
    ///
    /// Touches reach them through `spanTap`, so the text view's own action stands down unless
    /// VoiceOver or Switch Control is running: those activate a link through this action rather than
    /// a touch, and a touch path running beside it would open everything twice.
    public func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning else {
            switch textItem.content {
            case .link, .tag: return nil
            case .textAttachment: return defaultAction
            @unknown default: return defaultAction
            }
        }
        switch textItem.content {
        case .link(let url):
            return UIAction { [weak self] _ in self?.onOpenURL?(url) }
        case .tag(let tag):
            // The only tag `linkedText(for:)` sets is a mention's handle.
            guard let username = Username(tag) else { return nil }
            return UIAction { [weak self] _ in self?.onMentionTap?(username) }
        case .textAttachment:
            return defaultAction
        @unknown default:
            return defaultAction
        }
    }

    /// Suppress the per-link context menu so the cell's long-press "Copy" menu isn't shadowed.
    public func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        nil
    }
}

/// The rounded background drawn behind an `@handle`.
enum MentionPill {
    static let fill = UIColor.white.withAlphaComponent(0.14)
    /// Horizontal room between the handle's glyphs and the pill's edge.
    static let padding: CGFloat = 6
    /// Space between the pill's edge and the neighbouring words.
    static let gap: CGFloat = 3
    /// Kern either side of the handle, making room for the padding and the gap.
    static let spacing: CGFloat = padding + gap
    static let cornerRadius: CGFloat = 6

    /// The pill for one line of a mention, from that line's selection rect.
    static func rect(around line: CGRect) -> CGRect {
        line.insetBy(dx: -padding, dy: 0)
    }
}

/// A `UITextView` that shows text and taps links but refuses selection, the loupe, and the edit menu —
/// so the cell's long-press "Copy" context menu and the context-menu lift keep working. Mirrors
/// ChatLayout's own `MessageTextView` recipe.
final class LinkTextView: UITextView {
    private let pills = CAShapeLayer()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        pills.fillColor = MentionPill.fill.cgColor
        layer.insertSublayer(pills, at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var attributedText: NSAttributedString! {
        didSet { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawPills()
    }

    /// One pill per line a mention covers, behind the text, so a wrapped handle gets one on each line.
    private func drawPills() {
        let path = UIBezierPath()
        for rect in mentionPillRects {
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: MentionPill.cornerRadius))
        }
        pills.path = path.cgPath
        pills.frame = bounds
    }

    /// The pill behind each line of each mention, in the text view's coordinates.
    var mentionPillRects: [CGRect] {
        guard let text = attributedText, text.length > 0 else { return [] }
        var result: [CGRect] = []
        text.enumerateAttribute(.textItemTag, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value != nil, let lines = lineRects(for: range), let line = lines.first else { return }
            // The kern that opens room either side of the handle leaks into its selection rect: some
            // of the kern before it on the left, and the kern on its last letter on the right, except
            // at the end of a line where the text system drops it. So a handle on one line is sized
            // from its own letters, ending where its last letter does. One too long for a line keeps
            // its selection rects.
            guard lines.count == 1, let end = glyphEnd(ofLastCharacterIn: range, of: text) else {
                result += lines.map(MentionPill.rect(around:))
                return
            }
            let width = Self.unkerned(text.attributedSubstring(from: range)).size().width
            result.append(MentionPill.rect(around: CGRect(x: end - width, y: line.minY, width: width, height: line.height)))
        }
        return result
    }

    private func lineRects(for range: NSRange) -> [CGRect]? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let span = textRange(from: start, to: end)
        else { return nil }
        return selectionRects(for: span).map(\.rect).filter { $0.width > 0 }
    }

    /// Where the last letter of `range` ends, from where it starts plus its width without kern.
    private func glyphEnd(ofLastCharacterIn range: NSRange, of text: NSAttributedString) -> CGFloat? {
        let last = NSRange(location: range.location + range.length - 1, length: 1)
        guard let rect = lineRects(for: last)?.first else { return nil }
        return rect.minX + Self.unkerned(text.attributedSubstring(from: last)).size().width
    }

    private static func unkerned(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.removeAttribute(.kern, range: NSRange(location: 0, length: result.length))
        return result
    }

    override var isFocused: Bool { false }
    override var canBecomeFirstResponder: Bool { false }
    override var canBecomeFocused: Bool { false }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
#endif
