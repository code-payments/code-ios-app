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
import DifferenceKit

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

    /// Within this many points of the bottom counts as "at the bottom".
    private static let bottomThreshold: CGFloat = 50

    private let chatLayout = CollectionViewChatLayout()
    private var items: [ChatItem] = []
    /// Whether the user last left the transcript at the bottom. Updated only on user-driven
    /// scrolls, so content settling or the keyboard can't flip it — it's the gate for following
    /// the keyboard (an inset change) without yanking a reader who scrolled up.
    private var wasAtBottom = true
    /// True until the first non-empty content has been scrolled to the bottom. The open is
    /// deferred to `viewDidLayoutSubviews` so it runs once the collection view has real bounds.
    private var needsInitialScroll = false
    /// Breathing room kept below the last item, above the bar, so a trailing receipt doesn't sit
    /// flush against the bar.
    private static let bottomContentPadding: CGFloat = 12
    /// True while a batch update animates, so the top trigger doesn't re-fire mid-update.
    private var isUpdating = false

    public init() {
        super.init(collectionViewLayout: chatLayout)
        chatLayout.delegate = self
        chatLayout.settings.interItemSpacing = 8
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
        collectionView.register(ChatDateSeparatorCell.self, forCellWithReuseIdentifier: ChatDateSeparatorCell.reuseIdentifier)
        collectionView.register(ChatReceiptCell.self, forCellWithReuseIdentifier: ChatReceiptCell.reuseIdentifier)
        collectionView.reloadData()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        performInitialScrollIfNeeded()
    }

    public override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        // The system changed the adjusted inset — on-device this is the keyboard showing or hiding.
        // If the user was at the bottom, follow it so the newest message stays just above the
        // keyboard; a reader who scrolled up is left where they are.
        guard wasAtBottom, !needsInitialScroll, !isUpdating, !items.isEmpty else { return }
        scrollToBottom(animated: false)
    }

    // MARK: - Updates

    /// Replace the rendered transcript. Push-driven: the owner decides what's shown and when. The
    /// diff is computed by DifferenceKit and applied via `reload(using:)`, so
    /// `keepContentOffsetAtBottomOnBatchUpdates` keeps a new arrival pinned to the bottom (and a
    /// prepended older page anchored in place) with no hand-rolled scrolling.
    public func update(items newItems: [ChatItem]) {
        // The owner re-pushes on every observable change (read receipts, the live stream, paging
        // flags), most of which don't change the list. Bail on an identical push so we don't reload.
        guard newItems != items else { return }
        let wasEmpty = items.isEmpty
        if wasEmpty, !newItems.isEmpty {
            needsInitialScroll = true
        }
        guard isViewLoaded else {
            items = newItems
            return
        }

        // First load (or a clear): a plain reload, then open at the newest message rather than
        // animating every row in.
        if wasEmpty || newItems.isEmpty {
            items = newItems
            collectionView.reloadData()
            performInitialScrollIfNeeded()
            return
        }

        let changeset = StagedChangeset(source: items, target: newItems).flattenIfPossible()
        guard !changeset.isEmpty else {
            items = newItems
            return
        }
        isUpdating = true
        collectionView.reload(
            using: changeset,
            // A change too large to animate falls back to a reload that keeps the bottom-anchored
            // position rather than animating hundreds of rows.
            interrupt: { $0.changeCount > 100 },
            onInterruptedReload: { [weak self] in
                guard let self else { return }
                let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
                collectionView.reloadData()
                if let snapshot {
                    chatLayout.restoreContentOffset(with: snapshot)
                }
            },
            completion: { [weak self] _ in
                self?.isUpdating = false
            },
            setData: { [weak self] data in
                self?.items = data
            }
        )
    }

    // MARK: - Data source

    public override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch items[indexPath.item] {
        case .dateSeparator(_, let text):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatDateSeparatorCell.reuseIdentifier,
                for: indexPath
            ) as! ChatDateSeparatorCell
            cell.configure(text: text)
            return cell
        case .receipt(_, let text):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatReceiptCell.reuseIdentifier,
                for: indexPath
            ) as! ChatReceiptCell
            cell.configure(text: text)
            return cell
        case .message(let message):
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
    }

    // MARK: - Scrolling

    /// Open at the newest message once there is content and real bounds. Runs once — ChatLayout
    /// keeps it anchored afterwards.
    private func performInitialScrollIfNeeded() {
        guard needsInitialScroll, !items.isEmpty, collectionView.bounds.height > 0 else { return }
        needsInitialScroll = false
        scrollToBottom(animated: false)
    }

    /// Scroll to the newest message by re-anchoring the layout to the last item's bottom edge.
    /// This is ChatLayout's own primitive and is correct even before the bottom cells have
    /// self-sized — it positions the last item, not a globally-computed offset.
    public func scrollToBottom(animated: Bool = true) {
        guard !items.isEmpty else { return }
        let snapshot = ChatLayoutPositionSnapshot(
            indexPath: IndexPath(item: items.count - 1, section: 0),
            edge: .bottom
        )
        guard animated else {
            chatLayout.restoreContentOffset(with: snapshot)
            // The first restore positions by the estimate; once the bottom cells self-size, re-anchor
            // so a tall last cell (cash card, long message) sits fully above the bar, not short.
            DispatchQueue.main.async { [weak self] in
                self?.chatLayout.restoreContentOffset(with: snapshot)
            }
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
        })
    }

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
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

    /// Reserve room at the bottom for an overlaying bar (and the keyboard, when the screen pushes
    /// it up). The bottom-most visible item is captured and re-anchored across the inset change via
    /// ChatLayout's own snapshot, so at-bottom stays at-bottom (content lifts above the bar) and
    /// scrolled-up stays put — no hand-computed offset.
    public func setBottomInset(_ inset: CGFloat) {
        // Never change the inset mid-batch-update: ChatLayout can't account for an inset change
        // during `performBatchUpdates`, which is what made an append (a send) overshoot. The next
        // layout pass after the update re-applies it.
        let target = inset + Self.bottomContentPadding
        guard isViewLoaded, !isUpdating, abs(collectionView.contentInset.bottom - target) > 0.5 else { return }
        let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
        collectionView.contentInset.bottom = target
        collectionView.verticalScrollIndicatorInsets.bottom = target
        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
    }
}

/// `.auto` self-sizing and `.fullWidth` alignment fit the text/date/receipt rows, which size to
/// their own content. The cash card is a fixed 232×170 footprint, so it gets an exact height: an
/// inserted self-sizing cell is placed at the small estimate and relies on a follow-up self-size
/// pass that iOS 26 skips mid-animated-batch-update, leaving the card clipped to the estimate.
/// An exact size is applied on insert with no self-size pass, so it can't regress.
extension ChatViewController: ChatLayoutDelegate {
    public func sizeForItem(_ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath) -> ItemSize {
        if case .message(let message) = items[indexPath.item], case .cash = message.content {
            return .exact(CGSize(width: collectionView.bounds.width, height: ChatCashCardCell.cardSize.height))
        }
        return .auto
    }
}

#Preview("Transcript") {
    let controller = ChatViewController()
    controller.update(items: ChatMessage.previewConversation(count: 40).map { .message($0) })
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
