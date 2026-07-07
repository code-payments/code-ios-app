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
import FlipcashCore

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

    /// Called when the user taps a failed outgoing row to retry; the argument is the message's stable id.
    public var onRetry: ((String) -> Void)?

    /// Called when the user taps a cash card; the argument is the message's stable id. The owner opens
    /// that token's currency info. Only cash rows are selectable (see `shouldHighlightItemAt`).
    public var onCashCardTap: ((String) -> Void)?

    /// Called when the user taps a URL in a text bubble; the owner opens it.
    public var onOpenURL: ((URL) -> Void)?

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
    /// Set while `setBottomInset` writes the content inset — that write synchronously fires
    /// `scrollViewDidChangeAdjustedContentInset`, and this stops the delegate re-entering `scrollToBottom`
    /// → `restoreContentOffset` mid-write, a nested layout pass that crashes ChatLayout.
    private var isAdjustingBottomInset = false
    /// True while a context menu is lifted from a bubble. Presenting the menu dismisses the keyboard;
    /// without intervention the adjusted inset shrinks and the transcript reflows out from under the
    /// lifted preview. So for the menu's lifetime the inset is taken over and frozen at its keyboard-up
    /// value (see `freezeInset`): the keyboard's space stays reserved, so nothing moves — and the
    /// keyboard sliding back on dismiss restores everything to exactly where it was, matching iMessage.
    private var isShowingContextMenu = false
    /// The inset state captured when the menu opened, restored when it closes.
    private var savedInsetBehavior: UIScrollView.ContentInsetAdjustmentBehavior?
    private var savedContentInset: UIEdgeInsets?
    private var savedScrollIndicatorInsets: UIEdgeInsets?
    /// A transcript pushed while the menu was up, applied once it closes (so an arriving message can't
    /// reflow the content mid-preview). Mirrors ChatLayout deferring updates while `.showingPreview`.
    private var deferredItems: [ChatItem]?

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
        collectionView.register(ChatLinkMessageCell.self, forCellWithReuseIdentifier: ChatLinkMessageCell.reuseIdentifier)
        collectionView.register(ChatCashCardCell.self, forCellWithReuseIdentifier: ChatCashCardCell.reuseIdentifier)
        collectionView.register(ChatDateSeparatorCell.self, forCellWithReuseIdentifier: ChatDateSeparatorCell.reuseIdentifier)
        collectionView.register(ChatTypingIndicatorCell.self, forCellWithReuseIdentifier: ChatTypingIndicatorCell.reuseIdentifier)
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
        //
        // While a context menu is up the inset is frozen (`freezeInset`), so this shouldn't fire for the
        // keyboard — but guard anyway, since taking the inset over and handing it back each toggles the
        // adjusted inset, and following those would move the content the freeze is holding in place.
        guard !isAdjustingBottomInset, !isShowingContextMenu, wasAtBottom, !needsInitialScroll, !isUpdating, !items.isEmpty else { return }
        scrollToBottom(animated: false)
    }

    // MARK: - Updates

    /// Replace the rendered transcript. Push-driven: the owner decides what's shown and when. The
    /// diff is computed by DifferenceKit and applied via `reload(using:)`, so
    /// `keepContentOffsetAtBottomOnBatchUpdates` keeps a new arrival pinned to the bottom (and a
    /// prepended older page anchored in place) with no hand-rolled scrolling.
    public func update(items newItems: [ChatItem], animated: Bool = true) {
        // While a context menu is lifted, hold pushed updates: reloading the transcript now (e.g. an
        // arriving message) would reflow the content out from under the lifted preview. The latest
        // push is applied when the menu closes. Mirrors ChatLayout deferring updates during a preview.
        guard !isShowingContextMenu else {
            deferredItems = newItems
            return
        }
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

        // First load, a clear, or a non-animated update: reload in place and open at the newest
        // message rather than animating rows. A non-animated update (e.g. a late-resolving cash-card
        // detail) re-arms the open so the detail appears without the diff sliding it in.
        if wasEmpty || newItems.isEmpty || !animated {
            if !animated { needsInitialScroll = true }
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
        case .typingIndicator:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatTypingIndicatorCell.reuseIdentifier,
                for: indexPath
            ) as! ChatTypingIndicatorCell
        case .dateSeparator(_, let text):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatDateSeparatorCell.reuseIdentifier,
                for: indexPath
            ) as! ChatDateSeparatorCell
            cell.configure(text: text)
            return cell
        case .message(let message):
            switch message.content {
            case .text:
                // Only text messages are sent optimistically, so only they can reach the failed state
                // that arms retry (wired on both text cells). Cash messages are always server-confirmed.
                let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
                let maxWidth = width * Self.maxBubbleWidthFraction
                if message.linkPreview != nil {
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: ChatLinkMessageCell.reuseIdentifier,
                        for: indexPath
                    ) as! ChatLinkMessageCell
                    cell.configure(with: message, maxWidth: maxWidth)
                    cell.onRetry = { [weak self] id in self?.onRetry?(id) }
                    cell.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
                    return cell
                }
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ChatMessageCell.reuseIdentifier,
                    for: indexPath
                ) as! ChatMessageCell
                cell.configure(with: message, maxWidth: maxWidth)
                cell.onRetry = { [weak self] id in self?.onRetry?(id) }
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

    // MARK: - Selection

    /// Only cash cards are tappable — they open the token's currency info. Text bubbles and date
    /// separators opt out (a text row's only tap is retry, handled by its own recognizer). Gating
    /// highlight is enough to gate selection too: UIKit won't select a row it didn't highlight, and
    /// `didSelectItemAt` re-checks for cash as a backstop.
    public override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        cashMessageID(at: indexPath) != nil
    }

    public override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Selection here is a momentary tap action, not a persisted state — clear it immediately.
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let id = cashMessageID(at: indexPath) else { return }
        onCashCardTap?(id)
    }

    /// The stable id of the cash message at `indexPath`, or nil if that row isn't a cash card. The
    /// index is bounds-checked: a tap can race a batch update, where the index may outrun `items`.
    private func cashMessageID(at indexPath: IndexPath) -> String? {
        guard items.indices.contains(indexPath.item),
              case .message(let message) = items[indexPath.item], case .cash = message.content else { return nil }
        return message.id
    }

    /// The typing indicator's dot wave is driven here, not from the cell's `didMoveToWindow`: a recycled
    /// cell loses its `CAAnimation`s, and `willDisplay`/`didEndDisplaying` are the reliable per-appearance
    /// hooks, so the wave restarts every time the row is (re)inserted.
    public override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ChatTypingIndicatorCell)?.startAnimating()
    }

    public override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ChatTypingIndicatorCell)?.stopAnimating()
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
        // The inset is frozen while a context menu is up; don't touch it (it's restored on close).
        guard !isShowingContextMenu else { return }
        // Never change the inset mid-batch-update: ChatLayout can't account for an inset change
        // during `performBatchUpdates`, which is what made an append (a send) overshoot. The next
        // layout pass after the update re-applies it.
        let target = inset + Self.bottomContentPadding
        guard isViewLoaded, !isUpdating, abs(collectionView.contentInset.bottom - target) > 0.5 else { return }
        let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
        isAdjustingBottomInset = true // suppress the delegate re-entry from the inset write below
        collectionView.contentInset.bottom = target
        collectionView.verticalScrollIndicatorInsets.bottom = target
        isAdjustingBottomInset = false
        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    /// Take over the inset at its current (keyboard-up) value so the keyboard leaving under the menu
    /// can't shrink the adjusted inset — the keyboard's space stays reserved and the content holds its
    /// exact position. Switching `contentInsetAdjustmentBehavior` flashes a transient inset that
    /// ChatLayout would re-anchor to, so the bottom-edge snapshot is restored across the switch (the
    /// same primitive `setBottomInset` uses) to pin the content where it was.
    private func freezeInset() {
        guard savedInsetBehavior == nil else { return }
        let frozen = collectionView.adjustedContentInset
        let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
        savedInsetBehavior = collectionView.contentInsetAdjustmentBehavior
        savedContentInset = collectionView.contentInset
        savedScrollIndicatorInsets = collectionView.verticalScrollIndicatorInsets
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = frozen
        collectionView.verticalScrollIndicatorInsets = frozen
        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    /// Hand the inset back to the system; with the keyboard sliding back in, it re-grows the adjusted
    /// inset to its pre-menu value. The bottom-edge snapshot is restored across the switch so the
    /// content lands exactly where it was, rather than wherever the transient inset re-anchored it.
    private func restoreInset() {
        guard let behavior = savedInsetBehavior else { return }
        let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
        collectionView.contentInsetAdjustmentBehavior = behavior
        if let inset = savedContentInset { collectionView.contentInset = inset }
        if let indicator = savedScrollIndicatorInsets { collectionView.verticalScrollIndicatorInsets = indicator }
        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
        savedInsetBehavior = nil
        savedContentInset = nil
        savedScrollIndicatorInsets = nil
    }
}

/// The controller is the layout delegate so cells inherit ChatLayout's defaults — auto self-sizing
/// and full-width alignment. No row needs a custom size, so nothing is overridden.
extension ChatViewController: ChatLayoutDelegate {}

// MARK: - Context menu

extension ChatViewController {

    /// Long-pressing a text bubble offers a single "Copy" action that puts the message text on the
    /// pasteboard — ChatLayout's canonical copy interaction, scoped to text messages. Cash cards and
    /// date separators carry no copyable text and opt out.
    public override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // Don't offer a menu mid-batch-update: the index path may not line up with the rendered cell.
        guard !isUpdating else { return nil }

        let body: String
        switch items[indexPath.item] {
        case .message(let message):
            switch message.content {
            case .text(let text):
                body = text
            case .cash:
                return nil
            }
        case .dateSeparator:
            return nil
        case .typingIndicator:
            return nil
        }

        // Freeze the inset for the menu's lifetime so presenting it (which dismisses the keyboard)
        // doesn't shrink the adjusted inset and reflow the content out from under the lifted preview.
        isShowingContextMenu = true
        freezeInset()

        // The section/item pair, encoded as an NSString, resolves the cell back in `preview(for:)`.
        // ChatLayout's note: a custom NSCopying identifier crashes, so a plain string is used.
        let identifier = "\(indexPath.section)|\(indexPath.item)" as NSString
        return UIContextMenuConfiguration(identifier: identifier, previewProvider: nil) { _ in
            let copy = UIAction(title: "Copy", image: UIImage(systemName: SystemSymbol.doc.rawValue)) { _ in
                UIPasteboard.general.string = body
            }
            return UIMenu(title: "", children: [copy])
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        preview(for: configuration)
    }

    public override func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        preview(for: configuration)
    }

    /// The menu is closing — hand the inset back to the system (the keyboard slides back, restoring the
    /// content to exactly where it was), then apply any update that was pushed while it was up. A `nil`
    /// animator (no transition) runs immediately so the freeze can never get stuck on.
    public override func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        let resume: () -> Void = { [weak self] in
            guard let self else { return }
            // Restore the inset while the flag is still set, so the behavior switch's inset change is
            // suppressed (no stray scroll); then drop the flag and apply any held update.
            restoreInset()
            isShowingContextMenu = false
            if let pending = deferredItems {
                deferredItems = nil
                update(items: pending)
            }
        }
        if let animator {
            animator.addCompletion(resume)
        } else {
            resume()
        }
    }

    /// Builds the lift preview from the bubble alone, clipped to its shape. Without it UIKit lifts the
    /// whole side-hugging cell as a plain rectangle. Mirrors ChatLayout's `preview(for:)`.
    private func preview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let identifier = configuration.identifier as? String else { return nil }
        let components = identifier.split(separator: "|")
        guard components.count == 2,
              let section = Int(components[0]),
              let item = Int(components[1]),
              let cell = collectionView.cellForItem(at: IndexPath(item: item, section: section)) as? BubbleCarrying else {
            return nil
        }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = cell.liftPreviewMaskingPath
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: cell.liftPreviewView, parameters: parameters)
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

/// A message cell that can supply the view + shape for the context-menu lift preview, so the lift is
/// clipped to the bubble rather than the full side-hugging cell.
protocol BubbleCarrying {
    var liftPreviewView: UIView { get }
    var liftPreviewMaskingPath: UIBezierPath? { get }
}
#endif
