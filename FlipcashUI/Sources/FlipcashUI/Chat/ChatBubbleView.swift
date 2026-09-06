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

/// A single chat bubble: a multiline label over the shared `BubbleBackgroundView`, styled to
/// match the app's conversation design (white-opacity fill, hairline border, app font, flattened
/// inner corners on a same-sender run). Dumb — hand it a `ChatMessage` and it draws.
public final class ChatBubbleView: UIView {

    private let background = BubbleBackgroundView()
    private let label = UILabel()
    private let editedLabel = EditedMarker.makeLabel()
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

        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        addSubview(editedLabel)

        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quotePanel)

        labelTopToBubble = label.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        labelTopToQuote = label.topAnchor.constraint(
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
            labelTopToBubble,
            quoteZeroHeight,
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Bottom-trailing corner: the body's reservation run keeps the space clear, so the
            // marker lands on the last line where it fits and on the wrapped line where it doesn't.
            editedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -EditedMarker.trailingInset),
            editedLabel.bottomAnchor.constraint(equalTo: label.bottomAnchor),
        ])
    }

    /// The bubble's shape in its own coordinate space, for clipping the context-menu lift preview.
    /// The background is pinned to every edge, so its bounds match the bubble's.
    var maskingPath: UIBezierPath { background.maskingPath }

    public func configure(with message: ChatMessage) {
        label.attributedText = Self.displayText(for: message)
        editedLabel.isHidden = !Self.showsEditedMarker(for: message)

        // Deactivate before activating: with both top constraints live the layout is
        // unsatisfiable, and UIKit resolves that by breaking one at random.
        if let quote = message.quote {
            quotePanel.isHidden = false
            quotePanel.configure(with: quote)
            quoteZeroHeight.isActive = false
            labelTopToBubble.isActive = false
            labelTopToQuote.isActive = true
        } else {
            quotePanel.isHidden = true
            labelTopToQuote.isActive = false
            labelTopToBubble.isActive = true
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

    /// Whether the bubble draws the "Edited" marker: a revised message that still has a body to
    /// revise, so a tombstone or a cash row never carries one.
    public static func showsEditedMarker(for message: ChatMessage) -> Bool {
        switch message.content {
        case .text:    message.isEdited
        case .deleted: false
        case .cash:    false
        }
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
        case .cash:
            return nil
        }

        let bodyFont: UIFont = isPlaceholder
            ? .italicSystemFont(ofSize: 16)
            : .default(size: 16, weight: .medium)
        let bodyColor: UIColor = isPlaceholder ? UIColor.white.withAlphaComponent(0.55) : .white

        let result = NSMutableAttributedString(
            string: body,
            attributes: [.font: bodyFont, .foregroundColor: bodyColor]
        )

        if Self.showsEditedMarker(for: message) {
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
        ChatMessage(id: "2", text: "Pretty good.", sender: .me, isContinuedByNext: true),
        ChatMessage(id: "3", text: "This one is much longer to show the bubble wrap across several lines and hug its content nicely.", sender: .me, isContinuationFromPrevious: true),
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
#endif
