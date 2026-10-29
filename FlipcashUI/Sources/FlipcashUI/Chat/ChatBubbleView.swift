//
//  ChatBubbleView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// A button drawn inside a chat bubble: its label and what a tap does.
public struct ChatBubbleAction {
    public let title: String
    public let handler: @MainActor () -> Void

    public init(title: String, handler: @escaping @MainActor () -> Void) {
        self.title = title
        self.handler = handler
    }
}

/// A single chat bubble: a multiline label over the shared `BubbleBackgroundView`, styled to
/// match the app's conversation design (white-opacity fill, hairline border, app font, flattened
/// inner corners on a bubble run). Dumb — hand it a `ChatMessage` and it draws.
public final class ChatBubbleView: UIView {

    private let background = BubbleBackgroundView()
    private let label = UILabel()
    private let editedLabel = EditedMarker.makeLabel()
    /// The line under an unavailable message's bubble; hidden for every other row.
    private let hintLabel = UILabel()
    /// The update bubble's optional capsule; hidden for every other row and when no action is given.
    private let actionButton = UIButton(type: .system)
    /// The update bubble's body, under the title the main label carries; empty on every other row.
    private let detailLabel = UILabel()
    private var action: ChatBubbleAction?
    private(set) var quotePanel = ChatQuotePanelView()

    /// Forwarded from the panel: the stable id of the message to jump to.
    var onQuoteTap: ((String) -> Void)? {
        get { quotePanel.onTap }
        set { quotePanel.onTap = newValue }
    }

    /// Body pinned to the bubble's top, for a message with no quote.
    private var labelTopToBubble: NSLayoutConstraint!
    /// Body pinned below the quote panel, for a reply.
    private var labelTopToQuote: NSLayoutConstraint!
    /// Body insets from the bubble's edges, relaxed to nothing on a bare row so the emoji starts
    /// where the bubble's outer edge would.
    private var labelLeading: NSLayoutConstraint!
    private var labelTrailing: NSLayoutConstraint!
    private var labelBottom: NSLayoutConstraint!
    /// The background reaches the view's bottom edge, except on an unavailable row where the hint
    /// hangs below the bubble and the background stops under the body.
    private var backgroundBottomToBounds: NSLayoutConstraint!
    private var backgroundBottomToLabel: NSLayoutConstraint!
    private var hintBottom: NSLayoutConstraint!
    /// The update bubble's body closes the bubble when it has no capsule under it.
    private var detailBottom: NSLayoutConstraint!
    /// The action capsule sits under the body and takes over the body's bottom inset.
    private var actionTop: NSLayoutConstraint!
    private var actionBottom: NSLayoutConstraint!
    /// Active only while the capsule shows: a hidden button keeps its intrinsic width and would
    /// hold every text bubble at least that wide.
    private var actionLeading: NSLayoutConstraint!
    private var actionTrailing: NSLayoutConstraint!
    /// Whether the row currently draws bare, so `maskingPath` can decline to clip a lift preview to
    /// a bubble that is not drawn.
    private var isBare = false

    private static var bodyInset: CGFloat { ChatStyle.bubblePaddingX }
    private static var bodyPadding: CGFloat { ChatStyle.bubblePaddingY }
    private static let hintTopSpacing: CGFloat = 8
    private static let hintLeadingInset: CGFloat = 4
    /// The update bubble's insets and spacing, from Figma component 11420:13397. It stacks a title,
    /// a body and a capsule, so it takes the roomier card padding rather than a text bubble's.
    private static let updateInsetVertical: CGFloat = 12
    private static let updateInsetHorizontal: CGFloat = 14
    private static let updateSpacing: CGFloat = 10
    /// A bare row's padding. Smaller than a bubble's because the emoji carries its own margin
    /// inside its line box, and the transcript's rhythm is what is being matched, not the bubble's.
    private static let barePadding: CGFloat = 4
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

        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        addSubview(editedLabel)

        hintLabel.font = .default(size: 12, weight: .semibold)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.numberOfLines = 0
        hintLabel.isHidden = true
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.baseBackgroundColor = .white
        buttonConfig.baseForegroundColor = .black
        buttonConfig.cornerStyle = .capsule
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.appTextSmall
            return attributes
        }
        detailLabel.font = .appTextCaption
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        detailLabel.numberOfLines = 0
        detailLabel.isHidden = true
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)

        actionButton.configuration = buttonConfig
        actionButton.isHidden = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addAction(UIAction { [weak self] _ in self?.action?.handler() }, for: .primaryActionTriggered)
        addSubview(actionButton)

        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quotePanel)

        labelTopToBubble = label.topAnchor.constraint(equalTo: topAnchor, constant: Self.bodyPadding)
        labelTopToQuote = label.topAnchor.constraint(
            equalTo: quotePanel.bottomAnchor,
            constant: ChatQuotePanelView.bottomSpacing
        )
        quoteCollapse = [
            quotePanel.heightAnchor.constraint(equalToConstant: 0),
            quotePanel.widthAnchor.constraint(equalToConstant: 0),
        ]

        quoteTrailing = quotePanel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -ChatQuotePanelView.surroundInset
        )

        labelBottom = label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bodyPadding)
        backgroundBottomToBounds = background.bottomAnchor.constraint(equalTo: bottomAnchor)
        backgroundBottomToLabel = background.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: Self.bodyPadding)
        hintBottom = hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        labelLeading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.bodyInset)
        labelTrailing = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.bodyInset)
        detailBottom = detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.updateInsetVertical)
        actionTop = actionButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: Self.updateSpacing)
        actionBottom = actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.updateInsetVertical)
        actionLeading = actionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.updateInsetHorizontal)
        actionTrailing = actionButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.updateInsetHorizontal)

        NSLayoutConstraint.activate(quoteCollapse + [
            background.topAnchor.constraint(equalTo: topAnchor),
            backgroundBottomToBounds,
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),

            quotePanel.topAnchor.constraint(equalTo: topAnchor, constant: ChatQuotePanelView.surroundInset),
            quotePanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatQuotePanelView.surroundInset),
            labelTopToBubble,
            labelBottom,
            labelLeading,
            labelTrailing,

            hintLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: Self.bodyPadding + Self.hintTopSpacing),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hintLeadingInset),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            detailLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: Self.updateSpacing),
            detailLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: label.trailingAnchor),

            // Bottom-trailing corner: the body's reservation run keeps the space clear, so the
            // marker lands on the last line where it fits and on the wrapped line where it doesn't.
            editedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -EditedMarker.trailingInset),
            editedLabel.bottomAnchor.constraint(equalTo: label.bottomAnchor),
        ])
    }

    /// The bubble's shape in its own coordinate space, for clipping the context-menu lift preview.
    /// The background is pinned to every edge, so its bounds match the bubble's. `nil` on a bare
    /// row: there is no bubble to clip to, and a lift given no path casts no shadow.
    var maskingPath: UIBezierPath? { isBare ? nil : background.maskingPath }

    /// Flashes the bubble's ground to point the eye at this message after a jump.
    func flashAttention(startedAt start: CFTimeInterval = CACurrentMediaTime()) { background.flashAttention(startedAt: start) }

    /// Whether this bubble is currently flashing.
    var isFlashingAttention: Bool { background.isFlashingAttention }

    /// Fills the bubble; `quoteThumbnail` is where a quoted photo's thumbnail loads from, and
    /// `updateAction` is the capsule an `.updateApp` bubble draws, or nil for none.
    public func configure(
        with message: ChatMessage,
        quoteThumbnail: ChatMediaLocation? = nil,
        updateAction: ChatBubbleAction? = nil
    ) {
        label.attributedText = Self.displayText(for: message)
        // Read after the body, so VoiceOver gets the send time without the reveal drag.
        label.accessibilityValue = message.sentAt?.formattedChatMessageTime()
        editedLabel.textColor = ChatStyle.mutedText(isFromSelf: message.sender == .me)
        editedLabel.isHidden = !Self.showsEditedMarker(for: message) || message.rendersAsLargeEmoji
        isBare = message.rendersAsLargeEmoji

        let hint: String?
        let isUpdateBubble: Bool
        switch message.content {
        case .unavailable(.updateApp):
            hint = nil
            isUpdateBubble = true
        case .unavailable(let unavailableHint):
            hint = unavailableHint.text
            isUpdateBubble = false
        case .text, .cash, .deleted, .shareProfile, .media, .paymentRequest:
            hint = nil
            isUpdateBubble = false
        }
        action = isUpdateBubble ? updateAction : nil
        let showsAction = action != nil
        actionButton.configuration?.title = action?.title
        actionButton.isHidden = !showsAction

        // Deactivate before activating, as with the quote's top constraints below.
        hintLabel.text = hint
        hintLabel.isHidden = hint == nil
        // Cleared rather than only hidden: a hidden label's text would still widen the bubble.
        detailLabel.text = isUpdateBubble ? ChatMessage.UnavailableHint.updateApp.text : nil
        detailLabel.isHidden = !isUpdateBubble
        NSLayoutConstraint.deactivate([
            labelBottom, hintBottom, detailBottom, actionTop, actionBottom, actionLeading, actionTrailing,
            backgroundBottomToLabel, backgroundBottomToBounds,
        ])
        if hint != nil {
            NSLayoutConstraint.activate([backgroundBottomToLabel, hintBottom])
        } else if showsAction {
            NSLayoutConstraint.activate([backgroundBottomToBounds, actionTop, actionBottom, actionLeading, actionTrailing])
        } else if isUpdateBubble {
            NSLayoutConstraint.activate([backgroundBottomToBounds, detailBottom])
        } else {
            NSLayoutConstraint.activate([backgroundBottomToBounds, labelBottom])
        }
        let vertical = isBare ? Self.barePadding : isUpdateBubble ? Self.updateInsetVertical : Self.bodyPadding
        let horizontal = isBare ? 0 : isUpdateBubble ? Self.updateInsetHorizontal : Self.bodyInset
        labelTopToBubble.constant = vertical
        labelBottom.constant = -vertical
        labelLeading.constant = horizontal
        labelTrailing.constant = -horizontal

        // Deactivate before activating: with both top constraints live the layout is
        // unsatisfiable, and UIKit resolves that by breaking one at random.
        if let quote = message.quote {
            quotePanel.isHidden = false
            quotePanel.configure(with: quote, thumbnail: quoteThumbnail, onSent: message.sender == .me)
            NSLayoutConstraint.deactivate(quoteCollapse)
            quoteTrailing.isActive = true
            labelTopToBubble.isActive = false
            labelTopToQuote.isActive = true
        } else {
            quotePanel.isHidden = true
            quotePanel.clear()
            labelTopToQuote.isActive = false
            labelTopToBubble.isActive = true
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
            border: Self.border(for: message),
            identity: message.id
        )
    }

    /// Whether the bubble draws the "Edited" marker: a revised message that still has a body to
    /// revise, so a tombstone or a cash row never carries one.
    public static func showsEditedMarker(for message: ChatMessage) -> Bool {
        switch message.content {
        case .text:    message.isEdited
        case .deleted: false
        case .cash:    false
        case .unavailable, .shareProfile, .media, .paymentRequest: false
        }
    }

    /// The hinted unavailable bubbles draw dashed; the update bubble keeps the received wash under
    /// a fainter dashed outline, matching Android.
    static func border(for message: ChatMessage) -> BubbleBackgroundView.Border {
        switch message.content {
        case .unavailable(.updateApp):  .dashedOverWash
        case .unavailable(.askToResend), .unavailable(.resend): .dashed
        case .text, .cash, .deleted, .shareProfile, .media, .paymentRequest: .hairline
        }
    }

    /// The unavailable bubble's line: an alert glyph, then the copy, both muted.
    private static func unavailableText() -> NSAttributedString {
        let color = UIColor.white.withAlphaComponent(0.55)
        let font = UIFont.default(size: 15, weight: .medium)
        let attachment = NSTextAttachment()
        attachment.image = UIImage.icon(.exclamationCircle)
            .withTintColor(color, renderingMode: .alwaysOriginal)
        attachment.bounds = CGRect(x: 0, y: -2, width: 16, height: 16)

        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: 4]))
        result.append(NSAttributedString(
            string: ChatMessage.unavailableCopy,
            attributes: [.font: font, .foregroundColor: color]
        ))
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 22
        style.maximumLineHeight = 22
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// The update bubble's title; `detailLabel` carries the body beneath it.
    private static func updateAppText() -> NSAttributedString {
        NSAttributedString(
            string: ChatMessage.updateAppTitle,
            attributes: [
                .font: UIFont.appTextMedium,
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            ]
        )
    }

    /// The bubble's rendered text: the body, a muted italic placeholder for a tombstone, and the
    /// "Edited" marker's reservation where the sender has revised the message — the marker itself is
    /// a separate label pinned to the bubble's corner. `nil` for cash rows, which use a dedicated
    /// cell rather than this bubble.
    public static func displayText(for message: ChatMessage) -> NSAttributedString? {
        let body: String
        let isPlaceholder: Bool
        switch message.content {
        case .text(let text):
            body = text
            isPlaceholder = false
        case .deleted(let placeholder):
            body = placeholder
            isPlaceholder = true
        case .unavailable(.updateApp):
            return updateAppText()
        case .unavailable(.askToResend), .unavailable(.resend):
            return unavailableText()
        case .cash, .shareProfile, .media, .paymentRequest:
            return nil
        }

        let isFromSelf = message.sender == .me
        let bodyFont: UIFont = if isPlaceholder {
            .italicSystemFont(ofSize: ChatStyle.bodySize)
        } else if message.rendersAsLargeEmoji {
            .default(size: 48, weight: .medium)
        } else {
            ChatStyle.bodyFont
        }
        let bodyColor = isPlaceholder ? ChatStyle.mutedText(isFromSelf: isFromSelf) : ChatStyle.text(isFromSelf: isFromSelf)

        var attributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: bodyColor]
        if !message.rendersAsLargeEmoji {
            attributes.merge(ChatStyle.bodyLineAttributes(for: bodyFont)) { _, new in new }
        }
        let result = NSMutableAttributedString(string: body, attributes: attributes)

        if Self.showsEditedMarker(for: message), !message.rendersAsLargeEmoji {
            result.append(EditedMarker.reservation)
        }

        return result
    }
}

#Preview("Bubbles") {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 4
    stack.alignment = .leading
    stack.translatesAutoresizingMaskIntoConstraints = false

    let samples: [ChatMessage] = [
        ChatMessage(id: "1", text: "Hey! How's it going?", sender: .other),
        ChatMessage(id: "2", text: "Pretty good.", sender: .me, isContinuedByNext: true, joinsBubbleBelow: true),
        ChatMessage(id: "3", text: "This one is much longer to show the bubble wrap across several lines and hug its content nicely.", sender: .me, isContinuationFromPrevious: true, joinsBubbleAbove: true),
    ]
    for message in samples {
        let bubble = ChatBubbleView()
        bubble.configure(with: message)
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 290).isActive = true
        stack.addArrangedSubview(bubble)
    }

    let container = UIView()
    container.backgroundColor = UIColor(Color.backgroundMain)
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
    ])
    return container
}

#Preview("Unavailable bubbles") {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    stack.alignment = .leading
    stack.translatesAutoresizingMaskIntoConstraints = false

    let samples: [(ChatMessage, ChatBubbleAction?)] = [
        (ChatMessage(id: "1", content: .unavailable(.updateApp), sender: .other), nil),
        (ChatMessage(id: "2", content: .unavailable(.updateApp), sender: .other), ChatBubbleAction(title: "Update Flipcash") {}),
        (ChatMessage(id: "3", content: .unavailable(.askToResend(firstName: "Ada")), sender: .other), nil),
    ]
    for (message, action) in samples {
        let bubble = ChatBubbleView()
        bubble.configure(with: message, updateAction: action)
        bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(bubble)
    }

    let container = UIView()
    container.backgroundColor = UIColor(Color.backgroundMain)
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
    ])
    return container
}
#endif
