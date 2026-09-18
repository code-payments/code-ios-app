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

    private let bubble = LinkableBubbleView()
    private var bubbleMaxWidthConstraint: NSLayoutConstraint!
    /// Holds a carded bubble open at the transcript's full bubble width. The card is pinned to the
    /// bubble's sides and takes its width from the bubble, and the bubble takes its width from its
    /// text — so a message that was nothing but the link, whose text the card replaced, would
    /// otherwise collapse the bubble to its padding and the card to nothing with it. Not required,
    /// so the `<=` above still wins on a narrow transcript.
    private var bubbleCardWidthConstraint: NSLayoutConstraint!

    /// Called when the user taps a URL in the bubble.
    var onOpenURL: ((URL) -> Void)? {
        didSet { bubble.onOpenURL = onOpenURL }
    }

    /// Called when the user taps the card the bubble drew in place of a link.
    var onLinkCardTap: ((LinkCard) -> Void)? {
        didSet { bubble.onLinkCardTap = onLinkCardTap }
    }

    var bubbleView: LinkableBubbleView { bubble }

    /// Forwarded from the bubble's quote panel: the stable id of the row to jump to.
    var onQuoteTap: ((String) -> Void)? {
        get { bubbleView.onQuoteTap }
        set { bubbleView.onQuoteTap = newValue }
    }

    /// The view + shape the context-menu lift clips to.
    var liftPreviewView: UIView { bubble }
    var liftPreviewMaskingPath: UIBezierPath? { bubble.maskingPath }

    func flashAttention(startedAt start: CFTimeInterval) { bubble.flashAttention(startedAt: start) }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        installColumn(content: bubble)
        bubbleMaxWidthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        bubbleMaxWidthConstraint.isActive = true
        bubbleCardWidthConstraint = bubble.widthAnchor.constraint(equalToConstant: 280)
        bubbleCardWidthConstraint.priority = .defaultHigh
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func prepareForReuse() {
        super.prepareForReuse()
        bubble.prepareForReuse()
    }

    /// - Parameter maxWidth: the widest the bubble may grow before its text wraps.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        bubbleMaxWidthConstraint.constant = maxWidth
        bubbleCardWidthConstraint.constant = maxWidth
        bubbleCardWidthConstraint.isActive = message.linkPreview?.card != nil
        bubble.configure(with: message)
        updateColumn(for: message, authorImageData: authorImageData)
        // A failed row's whole column is the retry target (ChatColumnCell); disable the bubble's own
        // text-view link taps so a tap on a failed message retries the send rather than opening the URL.
        bubble.isUserInteractionEnabled = !message.isFailed
    }
}

extension ChatLinkMessageCell: BubbleCarrying {}
#endif
