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

    /// Called with the newest message someone else sent that has been on screen, each time it moves
    /// past the last one reported. Silent until the opening scroll has landed, and while
    /// ``reportsReads`` is off.
    public var onMessagesSeen: ((MessageID) -> Void)?
    /// Whether rows on screen count as read. The owner turns this off while the app is not in front;
    /// turning it back on reports what is on screen now.
    public var reportsReads = true {
        didSet { if reportsReads, !oldValue { scheduleReadReport() } }
    }

    /// Called when the user taps a failed outgoing row to retry; the argument is the message's stable id.
    public var onRetry: ((String) -> Void)?

    /// Called when the user taps a cash card; the argument is the message's stable id. The owner opens
    /// that token's currency info. Only cash rows are selectable (see `shouldHighlightItemAt`).
    public var onCashCardTap: ((String) -> Void)?

    /// Called when the user taps a URL in a text bubble; the owner opens it.
    public var onOpenURL: ((URL) -> Void)?

    /// Called when the user taps the card drawn in place of a link. The whole card goes back
    /// because the two kinds land in different places — a cash card opens its link, a token card
    /// pushes that token onto this chat's own stack — and only the owner holds that stack. Carries
    /// the stable id of the message the card came on.
    public var onLinkCardTap: ((LinkCard, String) -> Void)?

    /// Where a link card looks its link up. Each card subscribes for itself, so the transcript
    /// carries no resolution state and a lookup landing cannot change a row's diff.
    public weak var linkCardSource: (any LinkCardSource)?

    /// Called when the user taps the profile card's call to action; the owner opens the
    /// counterpart's contact card (or the add-contact sheet), same as the nav title.
    public var onContactAction: (() -> Void)?

    /// Called when the user taps the transcript's head card — the counterpart's in a tip DM, the
    /// chat's own in a group. The owner opens that subject's profile; nil disables the tap.
    public var onProfileTap: (() -> Void)?

    /// Called when the user taps the group card's "Invite People"; the owner hands out the
    /// chat's invite link. nil leaves the card without the offer.
    public var onGroupInvite: (() -> Void)?

    /// Called when the user taps an author's face in the gutter; the argument is that author's user
    /// id. Never fires in a DM, where no row draws one.
    public var onAuthorTap: ((UserID) -> Void)?

    /// Fired when a context-menu action other than Copy is chosen, with the row's id. Copy is handled
    /// here — it needs nothing the transcript does not already hold.
    /// Called with a quoted message's stable id when its panel is tapped.
    public var onQuoteTap: ((String) -> Void)?

    public var onMessageAction: ((String, MessageCapability) -> Void)?

    /// The widest a bubble may grow, as a share of the collection view's width.
    private static let maxBubbleWidthFraction: CGFloat = 0.78

    /// Avatar bytes for the transcript's authors and typists, keyed by user id. Empty in a DM, where
    /// no row is attributed. The owner fills it as pictures download; rows already on screen pick the
    /// new bytes up without a diff, since nothing about the row itself changed.
    public var authorAvatars: [UserID: Data] = [:] {
        didSet {
            guard authorAvatars != oldValue, isViewLoaded else { return }
            for cell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell),
                      items.indices.contains(indexPath.item) else { continue }
                switch items[indexPath.item] {
                case .message(let message):
                    configure(cell, with: message)
                case .typingIndicator(let typists):
                    (cell as? ChatTypingIndicatorCell)?.configure(typists: typists, imageData: authorAvatars)
                case .dateSeparator, .unreadDivider, .profileCard, .groupCard:
                    continue
                }
            }
        }
    }

    /// Within this many points of the bottom counts as "at the bottom".
    private static let bottomThreshold: CGFloat = 50

    /// The gap the transcript leaves between two rows, in three tiers. The same three Android
    /// picks from in `bottomSpacingFor`, at the same values, so a thread reads at one density on
    /// both platforms.
    ///
    /// ``normal`` is the layout's base spacing: any pairing `interItemSpacing(_:after:)` does not
    /// answer for takes it.
    private enum RowGap {
        /// Two messages from one sender inside the grouping window. Their facing corners are
        /// already flattened, so the run needs only enough air to keep the bubbles apart.
        static let tight: CGFloat = 5
        /// Two messages from one sender that the grouping window has broken apart, and either side
        /// of a date separator. The corners are round again, and the gap says what they no longer
        /// do — that these are separate moments.
        static let normal: CGFloat = 10
        /// A change of speaker, which reads as a break in the column rather than another row in
        /// the same run.
        static let wide: CGFloat = 15
    }

    private let chatLayout = CollectionViewChatLayout()
    private var items: [ChatItem] = []
    /// Whether the user last left the transcript at the bottom. Updated only on user-driven
    /// scrolls, so content settling or the keyboard can't flip it — it's the gate for following
    /// the keyboard (an inset change) without yanking a reader who scrolled up.
    private var wasAtBottom = true
    /// True until the first non-empty content has been scrolled to the bottom. The open is
    /// deferred to `viewDidLayoutSubviews` so it runs once the collection view has real bounds.
    private var needsInitialScroll = false
    /// Set once the open has decided between the bottom and the unread divider. A later re-armed
    /// open (a non-animated update) goes to the bottom as before, rather than back to the divider
    /// the reader may already have scrolled past.
    private var hasPlacedUnreadDivider = false

    /// Set once the opening scroll has landed. Until then the transcript sits wherever the first
    /// layout put it — at the bottom, for a chat that is about to move up to its unread divider —
    /// and reporting that frame would mark read everything the divider is there to point at.
    private var hasPositioned = false
    /// What this visit has reported read so far.
    private var readProgress = ReadProgress()
    /// Whether a read report is queued for the next main-queue turn, so a burst of scroll ticks
    /// evaluates the screen once.
    private var isReadReportQueued = false

    /// A row asked for before it was in `items` — the loader's window has to move first. The next
    /// update carrying it performs the scroll.
    private var pendingScrollTargetID: String?
    /// The row a jump is pointing at and when its flash began, held for the flash's length so a cell
    /// dequeued for that row mid-flash is lit too.
    private var attention: (id: String, startedAt: CFTimeInterval)?

    /// Bumped whenever a jump takes ownership of where the transcript sits. A scroll-to-bottom's
    /// deferred re-anchor captures the value it was queued under and gives way if the count has
    /// moved since, so a jump landing before that block runs isn't pulled back to the newest message.
    private var positionClaim = 0

    /// Drag a row towards the leading edge to reply to it. Owns its own recognizer and state — see
    /// `ChatSwipeToReply` for why it is exclusive with every other gesture here.
    private let swipeToReply = ChatSwipeToReply()
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
        chatLayout.settings.interItemSpacing = RowGap.normal
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
        collectionView.register(ChatUnreadDividerCell.self, forCellWithReuseIdentifier: ChatUnreadDividerCell.reuseIdentifier)
        collectionView.register(ChatTypingIndicatorCell.self, forCellWithReuseIdentifier: ChatTypingIndicatorCell.reuseIdentifier)
        collectionView.register(ChatProfileCardCell.self, forCellWithReuseIdentifier: ChatProfileCardCell.reuseIdentifier)
        collectionView.register(ChatGroupCardCell.self, forCellWithReuseIdentifier: ChatGroupCardCell.reuseIdentifier)

        swipeToReply.isBlocked = { [weak self] in
            guard let self else { return true }
            return self.isShowingContextMenu || self.isUpdating
        }
        swipeToReply.rowForSwipe = { [weak self] point in
            guard let self,
                  let indexPath = self.collectionView.indexPathForItem(at: point),
                  let cell = self.collectionView.cellForItem(at: indexPath) as? ChatColumnCell,
                  // The strip at the row's leading edge is the author's face, or empty transcript
                  // — see `ChatColumnCell.allowsReplySwipe(at:)`.
                  cell.allowsReplySwipe(at: cell.convert(point, from: self.collectionView)),
                  case .message(let message) = self.items[indexPath.item],
                  message.actions.contains(.reply)
            else { return nil }
            return (cell, message.messageID)
        }
        swipeToReply.onTrigger = { [weak self] stableID in
            self?.onMessageAction?(stableID, .reply)
        }
        collectionView.addGestureRecognizer(swipeToReply.recognizer)

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
            // Toggling `isEnabled` cancels the gesture, which settles the row — a recycled cell must
            // never inherit a translation from the row that was dragged before it.
            swipeToReply.recognizer.isEnabled = false
            swipeToReply.recognizer.isEnabled = true
            collectionView.reloadData()
            // A jump that was waiting on this update owns where the transcript lands, so it runs
            // instead of the opening scroll-to-bottom rather than after it: that scroll queues a
            // re-anchor for the next runloop turn, which would pull the transcript off the message
            // a beat after arriving on it.
            if !performPendingScrollIfLanded() {
                performInitialScrollIfNeeded()
            }
            scheduleReadReport()
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
                    // A message arriving while the reader sits at the bottom moves nothing, so
                    // no scroll event would report it.
                    scheduleReadReport()
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
        case .typingIndicator(let typists):
            (cell as! ChatTypingIndicatorCell).configure(typists: typists, imageData: authorAvatars)
        case .profileCard(let card):
            let profileTap: (() -> Void)? = onProfileTap == nil ? nil : { [weak self] in self?.onProfileTap?() }
            (cell as! ChatProfileCardCell).configure(
                with: card,
                onContactAction: { [weak self] in self?.onContactAction?() },
                onProfileTap: profileTap
            )
        case .groupCard(let card):
            let cardTap: (() -> Void)? = onProfileTap == nil ? nil : { [weak self] in self?.onProfileTap?() }
            let invite: (() -> Void)? = onGroupInvite == nil ? nil : { [weak self] in self?.onGroupInvite?() }
            (cell as! ChatGroupCardCell).configure(with: card, onTap: cardTap, onInvite: invite)
        case .dateSeparator(_, let text):
            (cell as! ChatDateSeparatorCell).configure(text: text)
        case .unreadDivider(let count):
            (cell as! ChatUnreadDividerCell).configure(count: count)
        case .message(let message):
            configure(cell, with: message)
        }
        return cell
    }

    /// Fills a message cell. Split out of `cellForItemAt` because an avatar landing re-runs it for
    /// the rows already on screen, which must render identically to a fresh dequeue.
    private func configure(_ cell: UICollectionViewCell, with message: ChatMessage) {
        let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
        // An attributed incoming row gives its leading gutter to the avatar, so the same fraction of
        // a narrower row — otherwise the widest bubbles in a group run past where they do in a DM.
        // Keyed off the transcript rather than this row's author, to match the inset the cell takes.
        let available = message.isAttributedTranscript && message.sender != .me
            ? width - ChatColumnCell.authorGutterWidth
            : width
        let maxWidth = available * Self.maxBubbleWidthFraction
        let authorImageData = message.author.flatMap { authorAvatars[$0.id] }
        (cell as? ChatColumnCell)?.onAuthorTap = { [weak self] userID in self?.onAuthorTap?(userID) }
        switch cell {
        // Only text messages are sent optimistically, so only they can reach the failed state
        // that arms retry (wired on both text cells). Cash messages are always server-confirmed.
        case let cell as ChatLinkMessageCell:
            // Before `configure`, which is where the card subscribes.
            cell.linkCardSource = linkCardSource
            cell.configure(with: message, maxWidth: maxWidth, authorImageData: authorImageData)
            cell.onRetry = { [weak self] id in self?.onRetry?(id) }
            cell.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
            cell.onLinkCardTap = { [weak self] card in self?.onLinkCardTap?(card, message.messageID) }
            cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
        case let cell as ChatMessageCell:
            cell.configure(with: message, maxWidth: maxWidth, authorImageData: authorImageData)
            cell.onRetry = { [weak self] id in self?.onRetry?(id) }
            cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
        case let cell as ChatCashCardCell:
            cell.configure(with: message, authorImageData: authorImageData)
        default:
            assertionFailure("Unhandled chat cell class for message row")
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
        reattachAttention(to: cell, at: indexPath)
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
    ///
    /// With an unread divider, the first open lands with the divider at the top of the visible area
    /// instead, unless every unread message fits on screen from the bottom.
    private func performInitialScrollIfNeeded() {
        guard needsInitialScroll, !items.isEmpty, collectionView.bounds.height > 0 else { return }
        needsInitialScroll = false
        scrollToBottom(animated: false)
        armReadReportingOnceLanded()
        guard !hasPlacedUnreadDivider,
              let divider = items.firstIndex(where: { if case .unreadDivider = $0 { true } else { false } })
        else { return }
        hasPlacedUnreadDivider = true
        // A date on the same gap is drawn above the divider and goes up with it, so the reader
        // lands on the day as well as the count.
        let headsDivider = divider > 0 && { if case .dateSeparator = items[divider - 1] { true } else { false } }()
        let indexPath = IndexPath(item: headsDivider ? divider - 1 : divider, section: 0)
        if isAboveVisibleArea(indexPath) {
            scrollToRowTop(indexPath)
            return
        }
        // The rows under the divider may not have self-sized yet, so ask again once they have —
        // queued behind `scrollToBottom`'s own re-anchor, and only if nothing has claimed the
        // position since.
        let claim = positionClaim
        DispatchQueue.main.async { [weak self] in
            guard let self, positionClaim == claim, isAboveVisibleArea(indexPath) else { return }
            scrollToRowTop(indexPath)
        }
    }

    /// Whether the row at `indexPath` starts above the top of the visible area.
    private func isAboveVisibleArea(_ indexPath: IndexPath) -> Bool {
        guard let frame = chatLayout.layoutAttributesForItem(at: indexPath)?.frame else { return false }
        return frame.minY < chatLayout.visibleBounds.minY
    }

    /// Scrolls the given row into view, or waits for the update that brings it in.
    public func scrollToMessage(id: String) {
        guard items.contains(where: { $0.messageID == id }) else {
            pendingScrollTargetID = id
            return
        }
        scrollToRow(id: id, animated: true)
    }

    /// Performs a deferred jump once the update that brought the row in has been applied, reporting
    /// whether one ran.
    ///
    /// A jump that runs also consumes the opening scroll-to-bottom: the two want the transcript in
    /// different places, and the message the user asked for wins.
    @discardableResult
    private func performPendingScrollIfLanded() -> Bool {
        guard let target = pendingScrollTargetID,
              items.contains(where: { $0.messageID == target }) else { return false }
        pendingScrollTargetID = nil
        needsInitialScroll = false
        scrollToRow(id: target, animated: false)
        // The jump lands synchronously, so it is the opening position as soon as it runs.
        hasPositioned = true
        return true
    }

    /// Centers a row that is already in `items` and flashes it, so the jump lands on a message the
    /// eye can pick out of the transcript rather than on an unmarked one in the middle of the screen.
    private func scrollToRow(id: String, animated: Bool) {
        guard let index = items.firstIndex(where: { $0.messageID == id }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        positionClaim += 1
        guard animated else {
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            flashAttention(forStableID: id)
            return
        }
        ChatMotion.scroll.animate {
            self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }
        // Alongside the scroll rather than after it: the flash's rise is shorter than the scroll's
        // settle, so the row is already lit when it arrives and there is no beat where the transcript
        // has stopped on a message that looks like every other one.
        flashAttention(forStableID: id)
    }

    /// Puts the top of the row at `indexPath` at the top of the visible area, without animating. The
    /// top-aligned counterpart to ``scrollToRow(id:animated:)``'s centering, for a heading the reader
    /// should read down from.
    private func scrollToRowTop(_ indexPath: IndexPath) {
        positionClaim += 1
        let claim = positionClaim
        // The reader is off the bottom now, so the keyboard must not pull them back down to it.
        wasAtBottom = false
        let snapshot = ChatLayoutPositionSnapshot(indexPath: indexPath, edge: .top)
        chatLayout.restoreContentOffset(with: snapshot)
        // Re-anchor once the rows above have self-sized, as `scrollToBottom` does for the bottom.
        DispatchQueue.main.async { [weak self] in
            guard let self, positionClaim == claim else { return }
            chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    /// Flashes the row with `stableID`, and holds it as the attention target for as long as the
    /// flash runs so `willDisplay` can re-attach it.
    ///
    /// The scroll before it only moves the offset — the row it lands on has no cell until the next
    /// layout — so the layout is forced here rather than the flash being deferred a runloop turn.
    /// Deferring doesn't work: the queued attempt can drain before any layout pass has run, and the
    /// flash has to start alongside the scroll rather than after it. That forced pass displays the
    /// arriving rows, so `willDisplay` lights the target; a row already on screen gets no
    /// `willDisplay`, which is what the direct attach below covers.
    private func flashAttention(forStableID stableID: String) {
        let now = CACurrentMediaTime()
        attention = (id: stableID, startedAt: now)
        collectionView.layoutIfNeeded()
        for cell in bubbleCells(forStableID: stableID) { cell.flashAttention(startedAt: now) }
    }

    /// Lights a cell that has just been displayed if it carries the row a jump is pointing at.
    ///
    /// A recycled cell loses its `CAAnimation`s, and a jump lands right when the transcript is
    /// re-dequeueing rows around the page that brought the target in — so without this the flash is
    /// dropped within a frame of starting. Re-attaching from the original start time joins the flash
    /// in progress, so a row displayed twice doesn't play it twice as long.
    private func reattachAttention(to cell: UICollectionViewCell, at indexPath: IndexPath) {
        guard let attention,
              items.indices.contains(indexPath.item),
              items[indexPath.item].messageID == attention.id else { return }
        guard CACurrentMediaTime() - attention.startedAt < ChatMotion.attentionDuration else {
            self.attention = nil
            return
        }
        (cell as? BubbleCarrying)?.flashAttention(startedAt: attention.startedAt)
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
        let claim = positionClaim
        guard animated else {
            chatLayout.restoreContentOffset(with: snapshot)
            // The first restore positions by the estimate; once the bottom cells self-size, re-anchor
            // so a tall last cell (cash card, long message) sits fully above the bar, not short.
            DispatchQueue.main.async { [weak self] in
                guard let self, positionClaim == claim else { return }
                chatLayout.restoreContentOffset(with: snapshot)
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
            guard self.positionClaim == claim else { return }
            self.chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?()
        scheduleReadReport()
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

    // MARK: - Read reporting

    /// Turns read reporting on once the opening scroll has landed, and reports what is on screen
    /// then.
    ///
    /// Armed two main-queue turns out, and the report runs a turn after that. The open re-anchors a
    /// turn after it scrolls. A divider that had not self-sized takes its second look in that same
    /// turn and re-anchors on the next. The report lands after both.
    private func armReadReportingOnceLanded() {
        guard !hasPositioned else { return }
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !hasPositioned else { return }
                hasPositioned = true
                scheduleReadReport()
            }
        }
    }

    /// Queues one evaluation of the rows on screen for the next main-queue turn, after the layout
    /// has caught up with whatever asked for it.
    private func scheduleReadReport() {
        guard hasPositioned, reportsReads, !isReadReportQueued else { return }
        isReadReportQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isReadReportQueued = false
            reportSeenMessages()
        }
    }

    /// Reports the newest message someone else sent that is on screen now, when it beats everything
    /// reported before it.
    private func reportSeenMessages() {
        // A batch update reschedules from its completion; mid-update the index paths can outrun
        // `items`.
        guard hasPositioned, reportsReads, !isUpdating, isViewLoaded else { return }
        let visibleBounds = chatLayout.visibleBounds
        let visible = (chatLayout.layoutAttributesForElements(in: visibleBounds) ?? []).compactMap { attributes -> ReadProgress.VisibleMessage? in
            guard attributes.representedElementCategory == .cell,
                  Self.isSeen(attributes.frame, in: visibleBounds),
                  let message = message(at: attributes.indexPath),
                  let serverID = message.serverID else { return nil }
            let isFromSelf = switch message.sender {
            case .me:    true
            case .other: false
            }
            return ReadProgress.VisibleMessage(id: serverID, isFromSelf: isFromSelf)
        }
        guard let seen = readProgress.advance(seeing: visible) else { return }
        onMessagesSeen?(seen)
    }

    /// Whether a row at `frame` has been seen: any part of it inside the unobscured area counts, as
    /// on Android, which reads a row from `visibleItemsInfo` however little of it shows.
    static func isSeen(_ frame: CGRect, in visibleBounds: CGRect) -> Bool {
        let overlap = frame.intersection(visibleBounds)
        return !overlap.isNull && overlap.height > 0
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
        let below = IndexPath(item: indexPath.item + 1, section: indexPath.section)

        // Checked before the senders, as Android does: a separator is the heading for the run under
        // it, so it takes the same air on both sides whatever it happens to separate.
        guard !isHeading(at: indexPath), !isHeading(at: below) else { return nil }

        // A pairing with no sender on one side is the profile card, which is not a bubble and keeps
        // the base spacing.
        guard let current = sender(at: indexPath), let next = sender(at: below) else { return nil }
        guard current == next else { return RowGap.wide }

        // In an attributed transcript the side is not the speaker: two people's incoming bubbles
        // both read as `.other`, and without this a change of author would take the tight gap that
        // belongs inside one run. A row with no author is a DM row, where the side is the speaker.
        let currentAuthor = message(at: indexPath)?.author?.id
        let nextAuthor = message(at: below)?.author?.id
        guard currentAuthor == nextAuthor else { return RowGap.wide }

        // Same sender: tight only while they are one bubble run. The typing indicator never joins
        // one, so the dots arriving after the counterpart's own message read as a new turn.
        return message(at: indexPath)?.joinsBubbleBelow == true ? RowGap.tight : nil
    }

    /// The message at `indexPath`, or nil for a row that is not one. Bounds-checked for the same
    /// reason ``sender(at:)`` is.
    private func message(at indexPath: IndexPath) -> ChatMessage? {
        guard items.indices.contains(indexPath.item),
              case .message(let message) = items[indexPath.item] else { return nil }
        return message
    }

    /// Whether the row at `indexPath` is a day header or the unread divider. Bounds-checked; out of
    /// range is not one.
    private func isHeading(at indexPath: IndexPath) -> Bool {
        guard items.indices.contains(indexPath.item) else { return false }
        switch items[indexPath.item] {
        case .dateSeparator, .unreadDivider: return true
        case .message, .typingIndicator, .profileCard, .groupCard: return false
        }
    }

    /// Which side of the thread the row at `indexPath` belongs to, or nil for a row that belongs to
    /// neither (a date separator, the unread divider, the profile or group card). The typing
    /// indicator counts as the counterpart: it is an incoming bubble in everything but content, so it
    /// should arrive like one and should not read as a change of speaker when it follows their
    /// message.
    ///
    /// Bounds-checked, because the layout can ask mid-batch-update, where an index path may outrun
    /// `items`.
    private func sender(at indexPath: IndexPath) -> ChatMessage.Sender? {
        guard items.indices.contains(indexPath.item) else { return nil }
        switch items[indexPath.item] {
        case .message(let message): return message.sender
        case .typingIndicator: return .other
        case .dateSeparator, .unreadDivider, .profileCard, .groupCard: return nil
        }
    }
}

extension ChatViewController: UIGestureRecognizerDelegate {
    /// Lets the tap-to-dismiss recognizer fire alongside the collection view's own scroll and
    /// selection recognizers, so lowering the keyboard never pre-empts a cell tap.
    ///
    /// Swipe-to-reply is the exception: it translates a cell, so running it beside the scroll would
    /// drag a row sideways mid-scroll, and running it beside the long-press would slide the row out
    /// from under its own lift preview. It is exclusive in both directions.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === swipeToReply.recognizer || otherGestureRecognizer === swipeToReply.recognizer {
            return false
        }
        return true
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

        // A split row copies the whole message, not the piece of it the row happens to draw.
        let body: String? = if case .text(let text) = message.content { message.part?.messageText ?? text } else { nil }
        let rowID = message.messageID
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
                case .reply, .edit, .delete, .report:
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

    /// The on-screen cell drawing the first row of the message with `stableID` — the row a split
    /// message's quote heads, and the one an edit spotlights.
    private func bubbleCell(forStableID stableID: String) -> BubbleCarrying? {
        guard let item = items.firstIndex(where: { $0.messageID == stableID }) else { return nil }
        return collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? BubbleCarrying
    }

    /// Every on-screen cell drawing a row of the message with `stableID`, so a jump lights the whole
    /// of a message that was split around its card.
    private func bubbleCells(forStableID stableID: String) -> [BubbleCarrying] {
        items.indices
            .filter { items[$0].messageID == stableID }
            .compactMap { collectionView.cellForItem(at: IndexPath(item: $0, section: 0)) as? BubbleCarrying }
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
                isContinuedByNext: isContinued,
                joinsBubbleAbove: isContinuation,
                joinsBubbleBelow: isContinued
            )
        }
    }
}

/// A message cell that can supply the view + shape for the context-menu lift preview, so the lift is
/// clipped to the bubble rather than the full side-hugging cell, and can flash its own ground when
/// the transcript jumps to it.
protocol BubbleCarrying {
    var liftPreviewView: UIView { get }
    var liftPreviewMaskingPath: UIBezierPath? { get }
    func flashAttention(startedAt start: CFTimeInterval)
}
#endif

private extension MessageCapability {

    /// The menu row's glyph. Lives here rather than on the action itself because `SystemSymbol` is
    /// this module's symbol registry, and `MessageCapability` is a core model.
    var menuSymbol: SystemSymbol {
        switch self {
        case .copy:   .doc
        case .reply:  .replyArrow
        case .edit:   .pencil
        case .delete: .trash
        case .report: .flag
        }
    }
}
