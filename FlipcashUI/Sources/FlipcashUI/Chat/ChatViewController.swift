//
//  ChatViewController.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import ChatLayout

/// A standalone chat transcript: a `ChatLayout`-backed collection view that opens at the
/// newest message and renders whatever `[ChatMessage]` it is handed. Dumb and push-driven —
/// it pulls nothing. The owner calls `update(messages:)`; there is no network, no database,
/// and no shared state inside.
///
/// All scroll positioning is ChatLayout's: the `keepContentOffsetAtBottomOnBatchUpdates` /
/// `keepContentAtBottomOfVisibleArea` settings keep the view anchored to the newest message as
/// content is appended, prepended, and self-sizes, and `restoreContentOffset(_:)` against the
/// last item's bottom edge does the explicit scroll-to-bottom. This controller never computes a
/// content offset by hand — doing so lands short while tall cells are still at their estimate.
public final class ChatViewController: UICollectionViewController {

    /// Called whenever the user is near the top, to request the next older page. Fired
    /// repeatedly (not latched) — the owner's loader is expected to be idempotent, which is
    /// what keeps paging from ever getting stuck on a page.
    public var onReachTop: (() -> Void)?

    /// The widest a bubble may grow, as a share of the collection view's width.
    private static let maxBubbleWidthFraction: CGFloat = 0.78

    /// The user must be at least this many viewport-heights from the bottom for the
    /// jump-to-bottom button to appear.
    private static let jumpButtonViewportThreshold: CGFloat = 1

    /// Within this many points of the bottom counts as "at the bottom".
    private static let bottomThreshold: CGFloat = 50

    private let chatLayout = CollectionViewChatLayout()
    private var messages: [ChatMessage] = []
    /// Whether the user last left the transcript at the bottom. Updated only on user-driven
    /// scrolls, so content settling or the keyboard can't flip it — it's the gate for following
    /// the keyboard (an inset change) without yanking a reader who scrolled up.
    private var wasAtBottom = true
    /// True until the first non-empty content has been scrolled to the bottom. The open is
    /// deferred to `viewDidLayoutSubviews` so it runs once the collection view has real bounds.
    private var needsInitialScroll = false
    /// True while a batch update animates, so the top trigger doesn't re-fire mid-update.
    private var isUpdating = false
    private var isJumpButtonVisible = false
    private var jumpButtonBottomConstraint: NSLayoutConstraint?

    /// A floating "scroll to newest" affordance, shown once the user is a screen or more up.
    private lazy var jumpButton: UIButton = {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: "chevron.down")
        config.cornerStyle = .capsule
        config.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.scrollToBottom(animated: true)
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.alpha = 0
        button.isUserInteractionEnabled = false
        return button
    }()

    public init() {
        super.init(collectionViewLayout: chatLayout)
        chatLayout.delegate = self
        chatLayout.settings.interItemSpacing = 4
        // ChatLayout owns the bottom anchoring: stay pinned to the newest message across batch
        // updates (so an append at the bottom follows and a prepend preserves position), and sit
        // content at the bottom when it's shorter than the viewport.
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.keepContentAtBottomOfVisibleArea = true
        chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
        // Estimated size lets ChatLayout place off-screen rows without measuring them; the
        // native cell self-sizes to its true height, so the estimate never clips content.
        chatLayout.settings.estimatedItemSize = CGSize(width: UIScreen.main.bounds.width, height: 56)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = UIColor(Color.backgroundMain)
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        // The adjusted content inset (safe area + the bar inset the owner sets) is how the keyboard
        // and bar reserve space; ChatLayout reads it for positioning, so let UIKit manage it.
        collectionView.contentInsetAdjustmentBehavior = .always
        // Let the system add the safe area + keyboard to both the content inset and the indicator
        // inset; we only ever add the bar's own height on top, so the two stay in lockstep.
        collectionView.automaticallyAdjustsScrollIndicatorInsets = true
        // Self-sizing cells need prefetching off and self-sizing invalidation on.
        collectionView.isPrefetchingEnabled = false
        collectionView.selfSizingInvalidation = .enabled
        chatLayout.supportSelfSizingInvalidation = true
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        collectionView.register(ChatCashCardCell.self, forCellWithReuseIdentifier: ChatCashCardCell.reuseIdentifier)
        setUpJumpButton()
        collectionView.reloadData()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionJumpButton()
        performInitialScrollIfNeeded()
    }

    public override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        // The system changed the adjusted inset — on-device this is the keyboard showing or hiding.
        // If the user was at the bottom, follow it so the newest message stays just above the
        // keyboard; a reader who scrolled up is left where they are.
        positionJumpButton()
        guard wasAtBottom, !needsInitialScroll, !isUpdating, !messages.isEmpty else { return }
        scrollToBottom(animated: false)
    }

    /// Pinned to the scroll view's *frame* guide (not its content), so it floats in place
    /// instead of scrolling away with the messages.
    private func setUpJumpButton() {
        collectionView.addSubview(jumpButton)
        let bottom = jumpButton.bottomAnchor.constraint(equalTo: collectionView.frameLayoutGuide.bottomAnchor, constant: -16)
        jumpButtonBottomConstraint = bottom
        NSLayoutConstraint.activate([
            jumpButton.widthAnchor.constraint(equalToConstant: 40),
            jumpButton.heightAnchor.constraint(equalToConstant: 40),
            jumpButton.trailingAnchor.constraint(equalTo: collectionView.frameLayoutGuide.trailingAnchor, constant: -16),
            bottom,
        ])
    }

    // MARK: - Updates

    /// Replace the rendered transcript. Push-driven: the owner decides what's shown and when.
    /// A pure prepend (older page) or append (new message) is sent as an `insertItems` batch
    /// update so ChatLayout can keep the content anchored; any other change reloads. Appends
    /// animate (new messages arriving while you watch); prepends never do.
    public func update(messages newMessages: [ChatMessage]) {
        // The owner re-pushes on every observable change (read receipts, the live stream, paging
        // flags), most of which don't change the list. Bail on an identical push — otherwise the
        // `else` below would `reloadData` and discard the scroll position on every re-render.
        guard newMessages != messages else { return }
        let old = messages
        messages = newMessages
        if old.isEmpty, !newMessages.isEmpty {
            needsInitialScroll = true
        }
        guard isViewLoaded else { return }

        if old.isEmpty || newMessages.isEmpty {
            collectionView.reloadData()
            performInitialScrollIfNeeded()
        } else if let prepended = prependedCount(old: old, new: newMessages) {
            insertItems(range: 0..<prepended, animated: false)
        } else if let appended = appendedCount(old: old, new: newMessages) {
            insertItems(range: (newMessages.count - appended)..<newMessages.count, animated: true)
        } else {
            // A change that's neither a clean prepend nor append. Reload, but keep the
            // bottom-anchored position so it doesn't jump.
            let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
            collectionView.reloadData()
            if let snapshot {
                chatLayout.restoreContentOffset(with: snapshot)
            }
        }
    }

    /// `new` ends with `old` (by id) → the prepended count; nil otherwise. Matched by id, not
    /// full value: prepending older messages re-groups the old boundary row (it gains a
    /// `groupedAbove`), which a value comparison would miss — sending the update to a reload that
    /// loses the scroll position. By id it stays a clean prepend that ChatLayout anchors.
    private func prependedCount(old: [ChatMessage], new: [ChatMessage]) -> Int? {
        guard new.count > old.count, new.suffix(old.count).map(\.id) == old.map(\.id) else { return nil }
        return new.count - old.count
    }

    /// `new` starts with `old` (by id) → the appended count; nil otherwise.
    private func appendedCount(old: [ChatMessage], new: [ChatMessage]) -> Int? {
        guard new.count > old.count, new.prefix(old.count).map(\.id) == old.map(\.id) else { return nil }
        return new.count - old.count
    }

    private func insertItems(range: Range<Int>, animated: Bool) {
        isUpdating = true
        let indexPaths = range.map { IndexPath(item: $0, section: 0) }
        let apply = {
            self.collectionView.performBatchUpdates {
                self.collectionView.insertItems(at: indexPaths)
            } completion: { [weak self] _ in
                self?.isUpdating = false
            }
        }
        if animated {
            apply()
        } else {
            UIView.performWithoutAnimation(apply)
        }
    }

    // MARK: - Data source

    public override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        messages.count
    }

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let message = messages[indexPath.item]
        switch message.content {
        case .text:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatMessageCell.reuseIdentifier,
                for: indexPath
            ) as! ChatMessageCell
            let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
            cell.configure(with: message, maxWidth: width * Self.maxBubbleWidthFraction)
            return cell
        case .cash:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatCashCardCell.reuseIdentifier,
                for: indexPath
            ) as! ChatCashCardCell
            cell.configure(with: message)
            return cell
        }
    }

    // MARK: - Scrolling

    /// Open at the newest message once there is content and real bounds. Runs once — ChatLayout
    /// keeps it anchored afterwards.
    private func performInitialScrollIfNeeded() {
        guard needsInitialScroll, !messages.isEmpty, collectionView.bounds.height > 0 else { return }
        needsInitialScroll = false
        scrollToBottom(animated: false)
    }

    /// Scroll to the newest message by re-anchoring the layout to the last item's bottom edge.
    /// This is ChatLayout's own primitive and is correct even before the bottom cells have
    /// self-sized — it positions the last item, not a globally-computed offset.
    public func scrollToBottom(animated: Bool = true) {
        guard !messages.isEmpty else { return }
        let snapshot = ChatLayoutPositionSnapshot(
            indexPath: IndexPath(item: messages.count - 1, section: 0),
            edge: .bottom
        )
        guard animated else {
            chatLayout.restoreContentOffset(with: snapshot)
            updateJumpButton()
            return
        }
        let target = chatLayout.collectionViewContentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
        guard target > collectionView.contentOffset.y else { return }
        UIView.animate(withDuration: 0.25, animations: {
            self.collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        }, completion: { _ in
            // Lock to the exact bottom edge once the animation lands (the estimate may have moved).
            self.chatLayout.restoreContentOffset(with: snapshot)
            self.updateJumpButton()
        })
    }

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateJumpButton()
        // Track "at the bottom" only from real user scrolling, so an inset change (keyboard) or
        // content settling doesn't flip it.
        if scrollView.isDragging || scrollView.isDecelerating {
            let maxOffset = chatLayout.collectionViewContentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            wasAtBottom = maxOffset - scrollView.contentOffset.y < Self.bottomThreshold
        }
        // Don't paginate while a batch update animates, or before the opening scroll-to-bottom has
        // run — on open the content sits at the top for a beat, which would otherwise fire a stray
        // older-page load.
        guard !isUpdating, !needsInitialScroll else { return }
        // ChatLayout's canonical reverse-pagination trigger: while within one screen of the top.
        // The owner's loader is guarded, so firing repeatedly is fine, and it inherently only
        // fires when scrolled up — which is exactly "paginate only while scrolled up".
        if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + scrollView.bounds.height {
            onReachTop?()
        }
    }

    /// Whether the jump-to-bottom button should show, given how far the user is from the bottom.
    static func shouldShowJumpButton(distanceFromBottom: CGFloat, viewportHeight: CGFloat) -> Bool {
        distanceFromBottom > viewportHeight * jumpButtonViewportThreshold
    }

    private func updateJumpButton() {
        let distanceFromBottom = chatLayout.collectionViewContentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom
            - collectionView.contentOffset.y
        let visible = Self.shouldShowJumpButton(
            distanceFromBottom: distanceFromBottom,
            viewportHeight: collectionView.bounds.height
        )
        guard visible != isJumpButtonVisible else { return }
        isJumpButtonVisible = visible
        jumpButton.isUserInteractionEnabled = visible
        UIView.animate(withDuration: 0.2) { self.jumpButton.alpha = visible ? 1 : 0 }
    }

    /// Reserve room at the bottom for an overlaying bar (and the keyboard, when the screen pushes
    /// it up). The bottom-most visible item is captured and re-anchored across the inset change via
    /// ChatLayout's own snapshot, so at-bottom stays at-bottom (content lifts above the bar) and
    /// scrolled-up stays put — no hand-computed offset.
    public func setBottomInset(_ inset: CGFloat) {
        // Never change the inset mid-batch-update: ChatLayout can't account for an inset change
        // during `performBatchUpdates`, which is what made an append (a send) overshoot. The next
        // layout pass after the update re-applies it.
        guard isViewLoaded, !isUpdating, abs(collectionView.contentInset.bottom - inset) > 0.5 else { return }
        let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
        collectionView.contentInset.bottom = inset
        collectionView.verticalScrollIndicatorInsets.bottom = inset
        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
        positionJumpButton()
    }

    /// Keep the jump button just above the bar (and keyboard), i.e. above the adjusted inset.
    private func positionJumpButton() {
        jumpButtonBottomConstraint?.constant = -(collectionView.adjustedContentInset.bottom + 16)
    }
}

/// Defaults give `.auto` self-sizing and `.fullWidth` alignment — exactly right for rows
/// that align their own bubble. Nothing to override.
extension ChatViewController: ChatLayoutDelegate {}

#Preview("Transcript") {
    let controller = ChatViewController()
    controller.update(messages: ChatMessage.previewConversation(count: 40))
    return controller
}

extension ChatMessage {
    /// A deterministic sample conversation for previews and tests — alternating senders with
    /// same-sender runs grouped, so corner-flattening and self-sizing are both exercised.
    static func previewConversation(count: Int) -> [ChatMessage] {
        let texts = [
            "Hey!", "How's it going?", "Pretty good — shipping a thing.",
            "Nice. Want to grab lunch later?", "Sure, around noon?",
            "This one is intentionally much longer so the bubble wraps across multiple lines and proves the cell self-sizes to its content.",
            "👍", "See you then.",
        ]
        let senders: [Sender] = (0..<count).map { $0 % 3 == 0 ? .other : .me }
        return (0..<count).map { i in
            ChatMessage(
                id: "msg-\(i)",
                text: texts[i % texts.count],
                sender: senders[i],
                isContinuationFromPrevious: i > 0 && senders[i - 1] == senders[i],
                isContinuedByNext: i < count - 1 && senders[i + 1] == senders[i]
            )
        }
    }
}
#endif
