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
    /// Collapses the panel when there is no quote, so a hidden view consumes no height.
    private var quoteZeroHeight: NSLayoutConstraint!

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
        textView.dataDetectorTypes = .link
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

        textTopToBubble = textView.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        textTopToQuote = textView.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        quoteZeroHeight = quotePanel.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),

            quotePanel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            quotePanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatQuotePanelView.horizontalInset),
            quotePanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChatQuotePanelView.horizontalInset),
            textTopToBubble,
            quoteZeroHeight,
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

    func prepareForReuse() {
        textView.resignFirstResponder()
        quotePanel.onTap = nil
    }

    public func configure(with message: ChatMessage) {
        // Shares the plain bubble's text builder so a link message gets the same body styling, the
        // same tombstone copy, and the same "Edited" reservation. Data detection still runs — the
        // text view is non-editable, so it detects over `attributedText` as it did over `text`.
        textView.attributedText = ChatBubbleView.displayText(for: message)
        editedLabel.isHidden = !ChatBubbleView.showsEditedMarker(for: message)

        // Deactivate before activating: with both top constraints live the layout is
        // unsatisfiable, and UIKit resolves that by breaking one at random.
        if let quote = message.quote {
            quotePanel.isHidden = false
            quotePanel.configure(with: quote)
            quoteZeroHeight.isActive = false
            textTopToBubble.isActive = false
            textTopToQuote.isActive = true
        } else {
            quotePanel.isHidden = true
            textTopToQuote.isActive = false
            textTopToBubble.isActive = true
            quoteZeroHeight.isActive = true
        }

        background.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.isContinuationFromPrevious,
                groupedBelow: message.isContinuedByNext
            ),
            identity: message.id
        )
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
