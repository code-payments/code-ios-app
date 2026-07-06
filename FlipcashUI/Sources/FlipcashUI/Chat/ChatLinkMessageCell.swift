//
//  ChatLinkMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A recycled cell for a text message that contains a link: a `LinkableBubbleView` whose URLs are
/// tappable, in a `ChatColumnCell` so the receipt sits below it. Picked over the plain `ChatMessageCell`
/// (a `UILabel`) only for messages with a link, so plain text keeps the cheaper path.
public final class ChatLinkMessageCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatLinkMessageCell"

    /// The widest the bubble may grow before its text wraps.
    static let maxWidth: CGFloat = 280

    private let bubble = LinkableBubbleView()
    private var bubbleMaxWidthConstraint: NSLayoutConstraint!

    /// Called when the user taps a URL in the bubble.
    var onOpenURL: ((URL) -> Void)? {
        didSet { bubble.onOpenURL = onOpenURL }
    }

    /// The view + shape the context-menu lift clips to.
    var liftPreviewView: UIView { bubble }
    var liftPreviewMaskingPath: UIBezierPath? { bubble.maskingPath }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        installColumn(content: bubble)
        bubbleMaxWidthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth)
        bubbleMaxWidthConstraint.isActive = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func prepareForReuse() {
        super.prepareForReuse()
        bubble.prepareForReuse()
    }

    /// - Parameter maxWidth: the widest the bubble may grow before its text wraps.
    public func configure(with message: ChatMessage, maxWidth: CGFloat) {
        bubbleMaxWidthConstraint.constant = maxWidth
        bubble.configure(with: message)
        updateColumn(for: message)
        // A failed row's whole column is the retry target (ChatColumnCell); disable the bubble's own
        // text-view link taps so a tap on a failed message retries the send rather than opening the URL.
        bubble.isUserInteractionEnabled = !message.isFailed
    }
}

extension ChatLinkMessageCell: BubbleCarrying {}
#endif
