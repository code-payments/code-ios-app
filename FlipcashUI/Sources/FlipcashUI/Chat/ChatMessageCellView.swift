//
//  ChatMessageCellView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore

/// One message drawn by the transcript's own cell, at the widths the transcript gives it, for lists
/// outside the transcript such as the pinned messages. Nothing inside the cell takes touches; with
/// `onSelect` set, the bubble as a whole is one button and the rest of the row ignores taps.
public struct ChatMessageCellView: UIViewRepresentable {

    let message: ChatMessage
    let authorImageData: Data?
    let linkCardSource: (any LinkCardSource)?
    let mediaURLResolver: ChatMediaURLResolver?
    let onSelect: (() -> Void)?
    let selectLabel: String?

    /// - Parameters:
    ///   - onSelect: Called when the bubble is tapped or activated; nil leaves the cell inert.
    ///   - selectLabel: What VoiceOver reads for the bubble's button.
    public init(
        message: ChatMessage,
        authorImageData: Data? = nil,
        linkCardSource: (any LinkCardSource)? = nil,
        mediaURLResolver: ChatMediaURLResolver? = nil,
        onSelect: (() -> Void)? = nil,
        selectLabel: String? = nil
    ) {
        self.message = message
        self.authorImageData = authorImageData
        self.linkCardSource = linkCardSource
        self.mediaURLResolver = mediaURLResolver
        self.onSelect = onSelect
        self.selectLabel = selectLabel
    }

    public func makeUIView(context: Context) -> Host {
        Host()
    }

    public func updateUIView(_ host: Host, context: Context) {
        host.show(Host.Content(
            message: message,
            authorImageData: authorImageData,
            linkCardSource: linkCardSource,
            mediaURLResolver: mediaURLResolver
        ))
        host.onSelect = onSelect
        host.accessibilityLabel = selectLabel
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView host: Host, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return host.fittingSize(width: width)
    }

    /// Holds the cell and re-runs its `configure` whenever the message or the width changes.
    public final class Host: UIView {

        struct Content {
            let message: ChatMessage
            let authorImageData: Data?
            let linkCardSource: (any LinkCardSource)?
            let mediaURLResolver: ChatMediaURLResolver?
        }

        private var cell: ChatColumnCell?
        private var cellIdentifier: String?
        private var content: Content?
        private var width: CGFloat = 0

        /// Called when the bubble is tapped; while nil the host takes no touches.
        var onSelect: (() -> Void)? {
            didSet {
                isUserInteractionEnabled = onSelect != nil
                isAccessibilityElement = onSelect != nil
            }
        }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityTraits = .button
            accessibilityIdentifier = "chat-message-cell-bubble"
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func show(_ content: Content) {
            self.content = content
            configure()
        }

        func fittingSize(width: CGFloat) -> CGSize {
            if width != self.width {
                self.width = width
                configure()
            }
            guard let cell else { return CGSize(width: width, height: 0) }
            cell.frame.size.width = width
            let height = cell.contentView.systemLayoutSizeFitting(
                CGSize(width: width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            return CGSize(width: width, height: height)
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            cell?.frame = bounds
        }

        /// The bubble's frame in the host, or nil for a cell that doesn't draw one.
        private var bubbleFrame: CGRect? {
            guard let bubble = (cell as? BubbleCarrying)?.liftPreviewView else { return nil }
            return bubble.convert(bubble.bounds, to: self)
        }

        // The bubble answers as one target, so nothing inside it (a link, a card's Pay) can fire,
        // and the avatar, the name and the row's empty width pass the touch on.
        public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard isUserInteractionEnabled, !isHidden, let bubbleFrame, bubbleFrame.contains(point) else { return nil }
            return self
        }

        public override var accessibilityFrame: CGRect {
            get { UIAccessibility.convertToScreenCoordinates(bubbleFrame ?? bounds, in: self) }
            set { super.accessibilityFrame = newValue }
        }

        public override func accessibilityActivate() -> Bool {
            guard let onSelect else { return false }
            onSelect()
            return true
        }

        @objc private func tapped() {
            onSelect?()
        }

        private func configure() {
            guard let content, width > 0 else { return }
            let message = content.message
            let cell = cell(for: message)
            // The same widths `ChatViewController.configure(_:with:)` gives the row.
            let available = message.isAttributedTranscript && message.sender != .me
                ? width - ChatColumnCell.authorGutterWidth
                : width
            let maxWidth = available * ChatViewController.maxBubbleWidthFraction
            let cardWidth = (width - ChatColumnCell.rowInset * 2) * ChatViewController.cashCardWidthFraction
            switch cell {
            case let cell as ChatLinkMessageCell:
                cell.linkCardSource = content.linkCardSource
                let isMessageCard = if case .message = message.linkPreview?.card { true } else { false }
                cell.configure(with: message, maxWidth: isMessageCard ? cardWidth : maxWidth, authorImageData: content.authorImageData)
            case let cell as ChatMessageCell:
                cell.configure(with: message, maxWidth: maxWidth, authorImageData: content.authorImageData)
            case let cell as ChatCashCardCell:
                cell.configure(with: message, maxWidth: cardWidth, authorImageData: content.authorImageData)
            case let cell as ChatShareProfileCell:
                cell.linkCardSource = content.linkCardSource
                cell.configure(with: message, maxWidth: available - ChatColumnCell.rowInset * 2, authorImageData: content.authorImageData)
            case let cell as ChatPaymentRequestCell:
                cell.configure(with: message, maxWidth: cardWidth, authorImageData: content.authorImageData)
            case let cell as ChatMediaCell:
                guard case .media(let media) = message.content else { return }
                cell.linkCardSource = content.linkCardSource
                let remote = content.mediaURLResolver?.location(for: media, canReact: message.canReact) { [weak self] _ in
                    self?.configure()
                }
                cell.configure(with: message, maxWidth: maxWidth, localImage: nil, remote: remote, authorImageData: content.authorImageData)
            default:
                assertionFailure("Unhandled chat cell class for a message")
            }
            invalidateIntrinsicContentSize()
        }

        /// The cell class the transcript draws `message` with, replacing the held one when it differs.
        private func cell(for message: ChatMessage) -> ChatColumnCell {
            let identifier = ChatItem.message(message).cellReuseIdentifier
            if let cell, cellIdentifier == identifier {
                return cell
            }
            self.cell?.removeFromSuperview()
            let next: ChatColumnCell = switch identifier {
            case ChatLinkMessageCell.reuseIdentifier: ChatLinkMessageCell(frame: bounds)
            case ChatCashCardCell.reuseIdentifier: ChatCashCardCell(frame: bounds)
            case ChatShareProfileCell.reuseIdentifier: ChatShareProfileCell(frame: bounds)
            case ChatPaymentRequestCell.reuseIdentifier: ChatPaymentRequestCell(frame: bounds)
            case ChatMediaCell.reuseIdentifier: ChatMediaCell(frame: bounds)
            default: ChatMessageCell(frame: bounds)
            }
            addSubview(next)
            cell = next
            cellIdentifier = identifier
            return next
        }
    }
}
