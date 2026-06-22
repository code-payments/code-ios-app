//
//  ChatMessageCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A recycled collection-view cell that hosts a `ChatBubbleView` and aligns it to the
/// leading or trailing edge by sender. Self-sizing: the bubble is pinned top/bottom and
/// capped at a *constant* max width supplied by the owner, so the label wraps at a known
/// width during self-sizing (a width relative to `contentView` doesn't bound the label —
/// its width floats while the cell is measured, and the text collapses to one line).
/// Dumb — `configure(with:maxWidth:)` is the only input; no data fetching, no shared state.
public final class ChatMessageCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatMessageCell"

    private let bubble = ChatBubbleView()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var maxWidthConstraint: NSLayoutConstraint!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)

        leadingConstraint = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        maxWidthConstraint = bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 280)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            maxWidthConstraint,
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter maxWidth: the widest the bubble may grow before its text wraps, in points.
    ///   The owner derives it from the collection view's width.
    public func configure(with message: ChatMessage, maxWidth: CGFloat) {
        bubble.configure(with: message)
        maxWidthConstraint.constant = maxWidth
        applyAlignment(isFromSelf: message.sender == .me)
    }

    /// Exactly one horizontal edge is pinned, so the bubble hugs its content and the
    /// opposite edge floats — the cell never holds both constraints active at once.
    private func applyAlignment(isFromSelf: Bool) {
        leadingConstraint.isActive = !isFromSelf
        trailingConstraint.isActive = isFromSelf
    }
}

#Preview("Cells") {
    let layout = UICollectionViewFlowLayout()
    layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
    layout.minimumLineSpacing = 4

    let samples: [ChatMessage] = [
        ChatMessage(id: "1", text: "First message from them.", sender: .other),
        ChatMessage(id: "2", text: "And a reply from me.", sender: .me, isContinuedByNext: true),
        ChatMessage(id: "3", text: "Second line, same sender, so the corner flattens.", sender: .me, isContinuationFromPrevious: true),
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
