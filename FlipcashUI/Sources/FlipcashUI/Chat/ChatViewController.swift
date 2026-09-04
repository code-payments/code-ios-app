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
/// All scroll positioning is ChatLayout's: `keepContentOffsetAtBottomOnBatchUpdates` keeps the
/// view anchored to the newest message as content is appended, prepended, and self-sizes, and
/// `restoreContentOffset(_:)` against the last item's bottom edge does the explicit
/// scroll-to-bottom. Content shorter than the viewport top-aligns. This controller never computes
/// a content offset by hand — doing so lands short while tall cells are still at their estimate.
public final class ChatViewController: UICollectionViewController {

    /// Called whenever the user is near the top, to request the next older page. Fired
    /// repeatedly (not latched) — the owner's loader is expected to be idempotent, which is
    /// what keeps paging from ever getting stuck on a page.
    public var onReachTop: (() -> Void)?
    /// Fired whenever the transcript's content moves, so an overlay pinned to a row — the edit
    /// spotlight — can follow it.
    public var onScroll: (() -> Void)?

    /// Called when the user taps a failed outgoing row to retry; the argument is the message's stable id.
    public var onRetry: ((String) -> Void)?

    /// Called when the user taps a cash card; the argument is the message's stable id. The owner opens
    /// that token's currency info. Only cash rows are selectable (see `shouldHighlightItemAt`).
    public var onCashCardTap: ((String) -> Void)?

    /// Called when the user taps a URL in a text bubble; the owner opens it.
    public var onOpenURL: ((URL) -> Void)?

    /// Called when the user taps the profile card's call to action; the owner opens the
    /// counterpart's contact card (or the add-contact sheet), same as the nav title.
    public var onContactAction: (() -> Void)?

    /// Called when the user taps the profile card header in a tip DM; nil disables the tap.
    public var onProfileTap: (() -> Void)?

    /// Fired when a context-menu action other than Copy is chosen, with the row's id. Copy is handled
    /// here — it needs nothing the transcript does not already hold.
    /// Called with a quoted message's stable id when its panel is tapped.
    public var onQuoteTap: ((String) -> Void)?

    public var onMessageAction: ((String, MessageCapability) -> Void)?

    /// The widest a bubble may grow, as a share of the collection view's width.
    private static let maxBubbleWidthFraction: CGFloat = 0.78

    /// Within this many points of the bottom counts as "at the bottom".
    private static let bottomThreshold: CGFloat = 50

    /// Extra spacing where the sender flips, on top of the base inter-item spacing, so a change of
    /// speaker reads as a break in the column rather than another row in the same run.
    private static let senderFlipExtraSpacing: CGFloat = 6

    private let chatLayout = CollectionViewChatLayout()
    private var items: [ChatItem] = []
    /// Whether the user last left the transcript at the bottom. Updated only on user-driven
    /// scrolls, so content settling or the keyboard can't flip it — it's the gate for following
    /// the keyboard (an inset change) without yanking a reader who scrolled up.
    private var wasAtBottom = true
    /// True until the first non-empty content has been scrolled to the bottom. The open is
    /// deferred to `viewDidLayoutSubviews` so it runs once the collection view has real bounds.
    private var needsInitialScroll = false

    /// A row asked for before it was in `items` — the loader's window has to move first. The next
    /// update carrying it performs the scroll.
    private var pendingScrollTargetID: String?
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
    /// The bubble a context menu has raised, held so the lift's elevation comes off the same view when
    /// the menu goes. Weak: the cell it belongs to can be recycled out from under the menu.
    private weak var liftedBubble: UIView?
    /// The inset state captured when the menu opened, restored when it closes.
    private var savedInsetBehavior: UIScrollView.ContentInsetAdjustmentBehavior?
    private var savedContentInset: UIEdgeInsets?
    private var savedScrollIndicatorInsets: UIEdgeInsets?
    /// A transcript pushed while the menu was up, applied once it closes (so an arriving message can't
    /// reflow the content mid-preview). Mirrors ChatLayout deferring updates while `.showingPreview`.
    private var deferredItems: [ChatItem]?
    /// A bottom inset requested while the inset was not the caller's to change — the menu had it
    /// frozen, or a batch update was in flight — applied as soon as it is. The bar can grow from a
    /// menu action (choosing Edit opens the editing banner) and can shrink from a send (a multiline
    /// draft collapsing), and both land inside one of those windows; without holding the request the
    /// transcript keeps the old bar's inset until some later layout pass corrects it.
    private var pendingBottomInset: CGFloat?

    /// Called as a context menu is presented and again as it starts to dismiss, each carrying the
    /// transition's animator so the screen can fade its own backdrop alongside the menu. UIKit hides
    /// the keyboard for the menu's lifetime but leaves the composer first responder, so the screen
    /// also uses these to make that an ordinary dismissal and to put the keyboard back afterwards.
    var onContextMenuWillPresent: ((UIContextMenuInteractionAnimating?) -> Void)?
    var onContextMenuDidDismiss: ((UIContextMenuInteractionAnimating?) -> Void)?
    /// Guards the lowering to once per menu — the display callback can fire for the lift and again
    /// for the menu itself.
    private var didLowerKeyboardForMenu = false

    /// Work handed over by a menu action to run, in order, once the menu has finished dismissing. A
    /// `becomeFirstResponder` issued from a `UIAction` is rejected while the menu still owns the
    /// screen, so choosing Edit parks the keyboard-raise here instead.
    private var pendingAfterContextMenu: [() -> Void] = []

    public init() {
        super.init(collectionViewLayout: chatLayout)
        chatLayout.delegate = self
        chatLayout.settings.interItemSpacing = 8
        // ChatLayout owns the bottom anchoring: stay pinned to the newest message across batch
        // updates (so an append at the bottom follows and a prepend preserves position). Content
        // shorter than the viewport top-aligns — the profile card sits under the nav bar with
        // messages flowing beneath it, iMessage-style.
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
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
        // A tap anywhere in the transcript lowers the keyboard, iMessage-style. It rides alongside
        // the cells' own recognizers (it doesn't cancel touches and recognizes simultaneously), so a
        // tap on a cash card still opens its currency info — the dismissal just happens too.
        let dismissKeyboardTap = UITapGestureRecognizer(target: self, action: #selector(lowerKeyboard))
        dismissKeyboardTap.cancelsTouchesInView = false
        dismissKeyboardTap.delegate = self
        collectionView.addGestureRecognizer(dismissKeyboardTap)
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
        collectionView.register(ChatProfileCardCell.self, forCellWithReuseIdentifier: ChatProfileCardCell.reuseIdentifier)
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
        // This fires inside UIKit's keyboard-adjustment animation block. Following
        // the bottom via ChatLayout's `restoreContentOffset` forces a layout pass
        // here, which aborts on iOS 26 (a UICollectionView bounds-change fading
        // assertion). The visible cells are already sized during a keyboard toggle,
        // so pin to the bottom by setting the offset directly — no forced re-anchor,
        // letting the layout settle with the keyboard's own pass.
        let bottom = collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        guard bottom > collectionView.contentOffset.y else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }

    // MARK: - Updates

    /// Replace the rendered transcript. Push-driven: the owner decides what's shown and when. The
    /// diff is computed by DifferenceKit and applied via `reload(using:)`, so
    /// `keepContentOffsetAtBottomOnBatchUpdates` keeps a new arrival pinned to the bottom (and a
    /// prepended older page anchored in place) with no hand-rolled scrolling.
    public func update(items newItems: [ChatItem], animated: Bool = true) {
        // A window that jumped hundreds of rows must not animate: it would draw a scroll through
        // content the user never asked to see.
        let animated = animated && pendingScrollTargetID == nil
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
            performPendingScrollIfLanded()
            return
        }

        let changeset = StagedChangeset(source: items, target: newItems)
        guard !changeset.isEmpty else {
            items = newItems
            return
        }
        isUpdating = true
        // `performBatchUpdates` inherits the enclosing animation's timing, which is the only way to
        // give ChatLayout's insertion a spring: the layout delegate below supplies the *starting*
        // state, this supplies the curve it travels on.
        ChatMotion.insertion.animate { [self] in
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
                    guard let self else { return }
                    isUpdating = false
                    if let inset = pendingBottomInset {
                        pendingBottomInset = nil
                        setBottomInset(inset)
                    }
                    performPendingScrollIfLanded()
                },
                setData: { [weak self] data in
                    self?.items = data
                }
            )
        }
    }

    // MARK: - Data source

    public override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = items[indexPath.item]
        // Dequeue by the item's `cellReuseIdentifier` — the same value folded into the diff
        // identity — so the class dequeued at a position always matches the one the diff promised
        // there, and a reconfigure can never land on a cell of a different class (UIKit forbids that).
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: item.cellReuseIdentifier, for: indexPath)
        switch item {
        case .typingIndicator:
            break
        case .profileCard(let card):
            let profileTap: (() -> Void)? = onProfileTap == nil ? nil : { [weak self] in self?.onProfileTap?() }
            (cell as! ChatProfileCardCell).configure(
                with: card,
                onContactAction: { [weak self] in self?.onContactAction?() },
                onProfileTap: profileTap
            )
        case .dateSeparator(_, let text):
            (cell as! ChatDateSeparatorCell).configure(text: text)
        case .message(let message):
            let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
            let maxWidth = width * Self.maxBubbleWidthFraction
            switch cell {
            // Only text messages are sent optimistically, so only they can reach the failed state
            // that arms retry (wired on both text cells). Cash messages are always server-confirmed.
            case let cell as ChatLinkMessageCell:
                cell.configure(with: message, maxWidth: maxWidth)
                cell.onRetry = { [weak self] id in self?.onRetry?(id) }
                cell.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
                cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
            case let cell as ChatMessageCell:
                cell.configure(with: message, maxWidth: maxWidth)
                cell.onRetry = { [weak self] id in self?.onRetry?(id) }
                cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
            case let cell as ChatCashCardCell:
                cell.configure(with: message)
            default:
                assertionFailure("Unhandled chat cell class for reuse identifier \(item.cellReuseIdentifier)")
            }
        }
        return cell
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

    // MARK: - Keyboard

    /// Lowers the keyboard from a transcript tap. Ends editing at the window so it reaches the
    /// composer, which lives in a sibling hosted bar outside this controller's view tree.
    @objc private func lowerKeyboard() {
        collectionView.window?.endEditing(true)
    }

    // MARK: - Scrolling

    /// Open at the newest message once there is content and real bounds. Runs once — ChatLayout
    /// keeps it anchored afterwards.
    private func performInitialScrollIfNeeded() {
        guard needsInitialScroll, !items.isEmpty, collectionView.bounds.height > 0 else { return }
        needsInitialScroll = false
        scrollToBottom(animated: false)
    }

    /// Scrolls the given row into view, or waits for the update that brings it in.
    public func scrollToMessage(id: String) {
        guard items.contains(where: { $0.differenceIdentifier.hasSuffix(":\(id)") }) else {
            pendingScrollTargetID = id
            return
        }
        scrollToRow(id: id, animated: true)
    }

    /// Performs a deferred jump once the update that brought the row in has been applied.
    private func performPendingScrollIfLanded() {
        guard let target = pendingScrollTargetID,
              items.contains(where: { $0.differenceIdentifier.hasSuffix(":\(target)") }) else { return }
        pendingScrollTargetID = nil
        scrollToRow(id: target, animated: false)
    }

    /// Centers a row that is already in `items`.
    private func scrollToRow(id: String, animated: Bool) {
        guard let index = items.firstIndex(where: { $0.differenceIdentifier.hasSuffix(":\(id)") }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard animated else {
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            return
        }
        ChatMotion.scroll.animate {
            self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }
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
        ChatMotion.scroll.animate {
            self.collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        } completion: { _ in
            // Lock to the exact bottom edge once the animation lands (the estimate may have moved).
            self.chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?()
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
        // The inset is frozen while a context menu is up; hold the request for the close instead.
        guard !isShowingContextMenu else {
            pendingBottomInset = inset
            return
        }
        // Never change the inset mid-batch-update: ChatLayout can't account for an inset change
        // during `performBatchUpdates`, which is what made an append (a send) overshoot. Hold it for
        // the update's completion rather than waiting for whatever layout pass happens to run next —
        // a send that also collapses a multiline field lands the bar's new height inside the update,
        // and dropping the request there left the bar animating to a height the transcript only
        // matched a pass later, as a snap.
        guard !isUpdating else {
            pendingBottomInset = inset
            return
        }
        let target = inset + Self.bottomContentPadding
        guard isViewLoaded, abs(collectionView.contentInset.bottom - target) > 0.5 else { return }
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
    /// exact position.
    private func freezeInset() {
        guard savedInsetBehavior == nil else { return }
        let frozen = collectionView.adjustedContentInset
        savedInsetBehavior = collectionView.contentInsetAdjustmentBehavior
        savedContentInset = collectionView.contentInset
        savedScrollIndicatorInsets = collectionView.verticalScrollIndicatorInsets
        // Order matters: copy the inset in *before* taking the behavior over. Switching to `.never`
        // first would drop the keyboard's contribution for one pass, shrinking the scrollable range
        // under a transcript that sits at its bottom — UIKit clamps the offset there and then, and
        // re-growing the inset does not put it back. Raising `contentInset` first only ever grows
        // the adjusted inset, so nothing clamps on the way through.
        collectionView.contentInset = frozen
        collectionView.verticalScrollIndicatorInsets = frozen
        collectionView.contentInsetAdjustmentBehavior = .never
        // No `restoreContentOffset` re-anchor here: forcing ChatLayout's layout
        // pass during the context-menu inset/keyboard transition aborts on
        // iOS 26 (a UICollectionView bounds-change "fading" assertion), whether
        // called synchronously or deferred. The inset takeover above already
        // pins the adjusted inset at its keyboard-up value, so the content holds
        // its position without a forced re-anchor.
    }

    /// Hand the inset back to the system, which re-derives the adjusted inset from wherever the
    /// keyboard is by then: back up behind the menu, in which case nothing moves, or gone, in which
    /// case the transcript settles into the space it vacated.
    private func restoreInset() {
        guard let behavior = savedInsetBehavior else { return }
        collectionView.contentInsetAdjustmentBehavior = behavior
        if let inset = savedContentInset { collectionView.contentInset = inset }
        if let indicator = savedScrollIndicatorInsets { collectionView.verticalScrollIndicatorInsets = indicator }
        savedInsetBehavior = nil
        savedContentInset = nil
        savedScrollIndicatorInsets = nil
        // No `restoreContentOffset` re-anchor (see `freezeInset`): forcing the
        // layout pass here aborts on iOS 26. Handing the inset behavior back lets
        // the system re-grow the adjusted inset as the keyboard returns; the
        // at-bottom follow in `scrollViewDidChangeAdjustedContentInset` settles
        // the position through the normal path once the menu flag is cleared.
    }
}

/// The controller is the layout delegate: cells inherit ChatLayout's defaults for sizing and
/// alignment, and the two hooks below carry the transcript's motion — how an inserted row starts,
/// and the extra breathing room where the speaker changes.
extension ChatViewController: ChatLayoutDelegate {

    public func initialLayoutAttributesForInsertedItem(
        _ chatLayout: CollectionViewChatLayout,
        at indexPath: IndexPath,
        modifying originalAttributes: ChatLayoutAttributes,
        on state: InitialAttributesRequestType
    ) {
        switch state {
        case .initial:
            ChatMotion.applyInsertionState(to: originalAttributes, sender: sender(at: indexPath))
        case .invalidation:
            // Still the same arrival — ChatLayout only asks this for an inserted row, once
            // self-sizing has resolved its real height. It overwrites the frame first, so the
            // starting state has to be re-stated rather than assumed to have survived.
            ChatMotion.applyInsertionState(to: originalAttributes, sender: sender(at: indexPath))
        }
    }

    public func interItemSpacing(_ chatLayout: CollectionViewChatLayout, after indexPath: IndexPath) -> CGFloat? {
        // Only a message→message pair with different senders widens. Any other pairing (into or out
        // of a separator, the typing indicator, the profile card) takes the base spacing.
        guard let current = sender(at: indexPath),
              let next = sender(at: IndexPath(item: indexPath.item + 1, section: indexPath.section)),
              current != next else { return nil }
        return chatLayout.settings.interItemSpacing + Self.senderFlipExtraSpacing
    }

    /// Which side of the thread the row at `indexPath` belongs to, or nil for a row that belongs to
    /// neither (a date separator, the profile card). The typing indicator counts as the counterpart:
    /// it is an incoming bubble in everything but content, so it should arrive like one and should
    /// not read as a change of speaker when it follows their message.
    ///
    /// Bounds-checked, because the layout can ask mid-batch-update, where an index path may outrun
    /// `items`.
    private func sender(at indexPath: IndexPath) -> ChatMessage.Sender? {
        guard items.indices.contains(indexPath.item) else { return nil }
        switch items[indexPath.item] {
        case .message(let message): return message.sender
        case .typingIndicator: return .other
        case .dateSeparator, .profileCard: return nil
        }
    }
}

extension ChatViewController: UIGestureRecognizerDelegate {
    /// Lets the tap-to-dismiss recognizer fire alongside the collection view's own scroll and
    /// selection recognizers, so lowering the keyboard never pre-empts a cell tap.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Context menu

extension ChatViewController {

    /// Long-pressing a row offers exactly the actions the message carries, in the order the mapper
    /// put them in. Rows with no actions — cash cards, tombstones, date separators — opt out.
    public override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        // Don't offer a menu mid-batch-update: the index path may not line up with the rendered cell.
        guard !isUpdating else { return nil }
        guard let menu = contextMenu(forItemAt: indexPath) else { return nil }


        // Freeze the inset for the menu's lifetime so presenting it (which dismisses the keyboard)
        // doesn't shrink the adjusted inset and reflow the content out from under the lifted preview.
        isShowingContextMenu = true
        freezeInset()

        // The section/item pair, encoded as an NSString, resolves the cell back in `preview(for:)`.
        // ChatLayout's note: a custom NSCopying identifier crashes, so a plain string is used.
        let identifier = "\(indexPath.section)|\(indexPath.item)" as NSString
        return UIContextMenuConfiguration(identifier: identifier, previewProvider: nil) { _ in menu }
    }

    /// The menu a row offers, or `nil` if it offers none. Built separately from the configuration so
    /// that presenting a menu and deciding what is in one stay independently answerable.
    func contextMenu(forItemAt indexPath: IndexPath) -> UIMenu? {
        guard indexPath.item < items.count,
              case .message(let message) = items[indexPath.item],
              !message.actions.isEmpty else { return nil }

        let body: String? = if case .text(let text) = message.content { text } else { nil }
        let rowID = message.id
        let handler = onMessageAction

        let children = message.actions.map { action in
            UIAction(
                title: action.title,
                image: UIImage(systemName: action.menuSymbol.rawValue),
                attributes: action.isDestructive ? .destructive : []
            ) { _ in
                switch action {
                case .copy:
                    if let body { UIPasteboard.general.string = body }
                case .reply, .edit, .delete:
                    handler?(rowID, action)
                }
            }
        }
        return UIMenu(title: "", children: children)
    }

    public override func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        preview(for: configuration)
    }

    public override func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        preview(for: configuration)
    }

    /// The menu is coming on screen — take the keyboard down now, so it leaves as the menu arrives
    /// rather than the instant the long press registers. The inset was frozen when the menu was
    /// configured, so its space stays reserved and the transcript holds position while it goes.
    /// Deliberately not inside the animator's block: the composer bar rides the keyboard's own
    /// notifications, and folding the resign into the menu's animation leaves the bar stranded at
    /// its keyboard-up position.
    public override func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        guard !didLowerKeyboardForMenu else { return }
        didLowerKeyboardForMenu = true
        onContextMenuWillPresent?(animator)
    }

    /// The menu is closing — hand the inset back to the system (the keyboard slides back, restoring the
    /// content to exactly where it was), then apply any update that was pushed while it was up. A `nil`
    /// animator (no transition) runs immediately so the freeze can never get stuck on.
    public override func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        // Ask for the keyboard back as the dismissal starts, not in its completion: waiting for the
        // menu to finish leaves a beat of empty composer before the keyboard moves. The inset is
        // still frozen at its keyboard-up value while it rises, so nothing reflows, and by the time
        // the completion hands the inset back the keyboard is where the system expects it.
        didLowerKeyboardForMenu = false
        onContextMenuDidDismiss?(animator)

        let resume: () -> Void = { [weak self] in
            guard let self else { return }
            // Restore the inset while the flag is still set, so the behavior switch's inset change is
            // suppressed (no stray scroll); then drop the flag and apply any held update.
            restoreInset()
            isShowingContextMenu = false
            if let liftedBubble {
                BubbleBackgroundView.lower(liftedBubble)
                self.liftedBubble = nil
            }
            if let inset = pendingBottomInset {
                pendingBottomInset = nil
                setBottomInset(inset)
            }
            if let pending = deferredItems {
                deferredItems = nil
                update(items: pending)
            }
            let held = pendingAfterContextMenu
            pendingAfterContextMenu = []
            for work in held { work() }
        }
        if let animator {
            animator.addCompletion(resume)
        } else {
            resume()
        }
    }

    /// Run `work` once no context menu is on screen — immediately if none is up, otherwise after the
    /// current one finishes dismissing.
    public func afterContextMenu(_ work: @escaping () -> Void) {
        guard isShowingContextMenu else { return work() }
        // Appended, not assigned: one menu action can queue several pieces of follow-up work — an
        // edit raises the keyboard *and* pins its spotlight — and an assignment would drop all but
        // the last.
        pendingAfterContextMenu.append(work)
    }

    /// A detached copy of the bubble carried by the row with `stableID`, or `nil` when that row is
    /// not on screen. The screen floats this above the backdrop blur so the message being edited
    /// stays sharp while the transcript behind it goes soft — a copy rather than a hole cut in the
    /// blur, because a `UIVisualEffectView` does not reliably honour a layer mask.
    func bubbleSnapshot(forStableID stableID: String) -> UIView? {
        guard let cell = bubbleCell(forStableID: stableID) else { return nil }
        let bubble = cell.liftPreviewView
        // UIKit hides the row's own bubble for as long as its lifted preview is on screen and
        // unhides it as the dismissal lands. Snapshotting in that window returns a view that is
        // blank rather than nil, which would float an empty copy and never be retried — so report
        // "not yet" and let the caller ask again.
        guard !bubble.isHidden, bubble.alpha > 0, !bubble.bounds.isEmpty else { return nil }
        guard let copy = bubble.snapshotView(afterScreenUpdates: true) else { return nil }
        // The snapshot renders the bubble's bounds, so the lift's shadow — drawn outside them — isn't
        // in it. Re-applied here, at the same values the menu used, so the message doesn't drop back
        // onto the transcript's plane the moment the menu that raised it goes.
        BubbleBackgroundView.raise(copy, shape: cell.liftPreviewMaskingPath)
        return copy
    }

    /// Where that row's bubble currently sits, in `space`'s coordinates, or `nil` when it is not on
    /// screen. The floated copy is re-framed from this as the keyboard and the bar reflow the
    /// transcript underneath it.
    func bubbleFrame(forStableID stableID: String, in space: UICoordinateSpace) -> CGRect? {
        guard let cell = bubbleCell(forStableID: stableID) else { return nil }
        let bubble = cell.liftPreviewView
        return space.convert(bubble.bounds, from: bubble)
    }

    private func bubbleCell(forStableID stableID: String) -> BubbleCarrying? {
        guard let item = items.firstIndex(where: { $0.id == stableID }) else { return nil }
        return collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? BubbleCarrying
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
        // The lift's elevation, put on the bubble itself because the preview won't carry one: a clear
        // background casts nothing, `shadowPath` or not. Taken off again in `willEndContextMenu`'s
        // completion — this is a live cell subview, not a copy.
        liftedBubble = cell.liftPreviewView
        BubbleBackgroundView.raise(cell.liftPreviewView, shape: cell.liftPreviewMaskingPath)
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
        return (0..<count).map { (i: Int) -> ChatMessage in
            let isContinuation = i > 0 && senders[i - 1] == senders[i]
            let isContinued = i < count - 1 && senders[i + 1] == senders[i]
            return ChatMessage(
                id: "msg-\(i)",
                text: texts[i % texts.count],
                sender: senders[i],
                isContinuationFromPrevious: isContinuation,
                isContinuedByNext: isContinued
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

private extension MessageCapability {

    /// The menu row's glyph. Lives here rather than on the action itself because `SystemSymbol` is
    /// this module's symbol registry, and `MessageCapability` is a core model.
    var menuSymbol: SystemSymbol {
        switch self {
        case .copy:   .doc
        case .reply:  .arrowLeft
        case .edit:   .pencil
        case .delete: .trash
        }
    }
}
