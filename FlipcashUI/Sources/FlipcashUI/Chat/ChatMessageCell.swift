//
//  ChatMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A recycled collection-view cell that hosts a `ChatBubbleView` in a `ChatColumnCell`. The bubble is
/// capped at a *constant* max width supplied by the owner, so the label wraps at a known width during
/// self-sizing (a width relative to `contentView` doesn't bound the label — its width floats while the
/// cell is measured, and the text collapses to one line). Dumb — `configure(with:maxWidth:)` is the
/// only input; no data fetching, no shared state.
public final class ChatMessageCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatMessageCell"

    private let bubble = ChatBubbleView()
    private let reactionRow = ReactionPillRowView()
    private var reactionRowWidthConstraint: NSLayoutConstraint!
    private var maxWidthConstraint: NSLayoutConstraint!

    /// The bubble view, exposed so the controller can build a context-menu lift preview that clips
    /// to the bubble shape.
    var bubbleView: ChatBubbleView { bubble }

    /// Forwarded from the bubble's quote panel: the stable id of the row to jump to.
    var onQuoteTap: ((String) -> Void)? {
        get { bubbleView.onQuoteTap }
        set { bubbleView.onQuoteTap = newValue }
    }

    /// Fired when the viewer taps a reaction pill — the argument is the toggled emoji.
    var onReactionTap: ((String) -> Void)?
    /// Fired on a long-press of a reaction pill, to open the reactors sheet scoped to that emoji.
    var onReactionLongPress: ((String) -> Void)?
    /// Fired when the trailing "+" is tapped, to open the picker.
    var onReactionAdd: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        installColumn(content: bubble, accessory: reactionRow)
        maxWidthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        maxWidthConstraint.isActive = true
        // The pills get the widest a bubble can be, not this bubble's width, so a short message's
        // row stays on one line; `configure` keeps it in step with `maxWidth`.
        reactionRowWidthConstraint = reactionRow.widthAnchor.constraint(equalToConstant: 280)
        reactionRowWidthConstraint.isActive = true

        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func prepareForReuse() {
        super.prepareForReuse()
        reactionRow.prepareForReuse()
    }

    /// - Parameter maxWidth: the widest the bubble may grow before its text wraps, in points.
    ///   The owner derives it from the collection view's width.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        bubble.configure(with: message)
        maxWidthConstraint.constant = maxWidth
        reactionRowWidthConstraint.constant = maxWidth
        reactionRow.layoutWidth = maxWidth
        reactionRow.hugsTrailingEdge = message.sender == .me
        reactionRow.configure(pills: message.reactions, canReact: message.canReact)
        updateColumn(
            for: message,
            authorImageData: authorImageData,
            showsEditedMarker: message.rendersAsLargeEmoji && ChatBubbleView.showsEditedMarker(for: message)
        )
    }
}

extension ChatMessageCell: BubbleCarrying {
    var liftPreviewView: UIView { bubbleView }
    var liftPreviewMaskingPath: UIBezierPath? { bubbleView.maskingPath }
    func flashAttention(startedAt start: CFTimeInterval) { bubbleView.flashAttention(startedAt: start) }
}

#Preview("Cells") {
    let layout = UICollectionViewFlowLayout()
    layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
    layout.minimumLineSpacing = 4

    let samples: [ChatMessage] = [
        ChatMessage(id: "1", text: "First message from them.", sender: .other),
        ChatMessage(id: "2", text: "And a reply from me.", sender: .me, isContinuedByNext: true, joinsBubbleBelow: true),
        ChatMessage(id: "3", text: "Second line, joins the bubble run, so the corner flattens.", sender: .me, isContinuationFromPrevious: true, joinsBubbleAbove: true),
        ChatMessage(id: "4", text: "A longer one back from them that wraps onto more than a single line to prove self-sizing.", sender: .other),
    ]

    return ChatMessageCellPreviewController(messages: samples, layout: layout)
}

/// Minimal collection view that renders sample cells for the preview — exercises real
/// dequeue/recycle, not a hand-built stack.
private final class ChatMessageCellPreviewController: UICollectionViewController {
    private let messages: [ChatMessage]

    init(messages: [ChatMessage], layout: UICollectionViewLayout) {
        self.messages = messages
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .systemBackground
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        messages.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
        cell.configure(with: messages[indexPath.item], maxWidth: collectionView.bounds.width * 0.78)
        return cell
    }
}
#endif
