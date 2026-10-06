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
    /// Fired when a shared-profile widget's Share button is tapped, with the person's display name
    /// once the lookup has resolved it.
    public var onShareProfile: ((LinkCard.User, String?) -> Void)?

    /// The viewer's own profile, which a shared-profile widget naming them draws from directly. Rows
    /// on screen pick a change up without a diff.
    public var ownProfile: OwnProfileCard? {
        didSet {
            guard ownProfile != oldValue, isViewLoaded else { return }
            for cell in collectionView.visibleCells where cell is ChatShareProfileCell {
                guard let indexPath = collectionView.indexPath(for: cell),
                      items.indices.contains(indexPath.item),
                      case .message(let message) = items[indexPath.item] else { continue }
                configure(cell, with: message)
            }
        }
    }

    /// Called when the user taps an `@handle` in a text bubble; the owner finds who it names.
    public var onMentionTap: ((Username) -> Void)?

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
    /// Called when the "Encrypted" marker is tapped; nil leaves it inert.
    public var onEncryptionMarkerTap: (() -> Void)?

    /// Called when the user taps an author's face in the gutter; the argument is that author's user
    /// id. Never fires in a DM, where no row draws one.
    public var onAuthorTap: ((UserID) -> Void)?

    /// Fired when a context-menu action other than Copy is chosen, with the row's id. Copy is handled
    /// here — it needs nothing the transcript does not already hold.
    /// Called with a quoted message's stable id when its panel is tapped.
    public var onQuoteTap: ((String) -> Void)?

    public var onMessageAction: ((String, MessageCapability) -> Void)?

    /// Fired when the viewer taps a reaction pill on a message row: the row's stable id and the
    /// toggled emoji. Not folded into `onMessageAction`/`MessageCapability` — a reaction toggle is
    /// not a capability the context menu offers, and a group previewer without reply/edit/etc. can
    /// still reach this.
    public var onReactionTap: ((String, String) -> Void)?
    /// Fired on a long-press of a reaction pill: the row's stable id and the long-pressed emoji, to
    /// open the reactors sheet scoped to it.
    public var onReactionLongPress: ((String, String) -> Void)?
    /// Fired when a message row's trailing "+" reaction pill is tapped, to open the picker for that
    /// row's stable id.
    public var onReactionAdd: ((String) -> Void)?
    /// Fired when a photo row's image is tapped, to open the full-screen viewer. Never fires for a
    /// BlurHash-only or failed row, or one with nothing to show yet.
    public var onMediaTap: ((ChatMediaViewerRequest) -> Void)?

    /// Where a photo row gets its download URL. Nil draws every photo from its BlurHash.
    public var mediaURLResolver: ChatMediaURLResolver?

    /// The local image of a photo this device is still sending, by the pending row's id; the row draws
    /// it until the send confirms and the download takes over.
    public var pendingMediaImage: ((String) -> UIImage?)?

    /// The send progress of a photo this device is still sending, by the pending row's id; the row
    /// draws it over the photo until the send confirms or fails.
    public var pendingMediaProgress: ((String) -> ChatPhotoSendProgress?)?

    /// The widest a bubble may grow, as a share of the collection view's width.
    private static let maxBubbleWidthFraction: CGFloat = 0.78

    /// A cash card's width as a fraction of the row between the column insets — narrower than a
    /// bubble, and taken of the inset row rather than the full width. Matches Android's
    /// `CASH_CARD_WIDTH_FRACTION` so the card reads the same size on both.
    private static let cashCardWidthFraction: CGFloat = 0.64

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
                case .dateSeparator, .unreadDivider, .profileCard, .groupCard, .encryptionMarker:
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
    /// The first row of the new block appended at the bottom by the batch in flight, or nil when the
    /// batch appends nothing there. Those rows start below their slots (see `insertionRise(for:frame:)`).
    private var appendedFrom: Int?
    /// How far that appended block starts below its slots, worked out once from its first row so
    /// every row in it travels the same distance.
    private var appendedRise: CGFloat?
    /// The row the batch in flight grows out of the typing bubble, or nil. It starts in its slot,
    /// whole and unscaled, since its cell plays the arrival itself (see `ChatColumnCell.grow`).
    private var growingFromTyping: Int?
    /// Set while `setBottomInset` writes the content inset — that write synchronously fires
    /// `scrollViewDidChangeAdjustedContentInset`, and this stops the delegate re-entering `scrollToBottom`
    /// → `restoreContentOffset` mid-write, a nested layout pass that crashes ChatLayout.
    private var isAdjustingBottomInset = false
    /// True while a bubble is lifted over the transcript for its menu or reaction strip. The lift
    /// lowers the keyboard; without intervention the adjusted inset shrinks and the transcript
    /// reflows out from under the lifted bubble. So for the lift's lifetime the inset is taken over
    /// and frozen at its keyboard-up value (see `freezeInset`): the keyboard's space stays reserved,
    /// so nothing moves — and the keyboard sliding back on dismiss restores everything to exactly
    /// where it was, matching iMessage.
    private var isShowingContextMenu = false
    /// The adjusted bottom inset held while a menu is up, and the content inset it replaced.
    private var frozenBottomInset: CGFloat?
    private var savedContentInset: UIEdgeInsets?
    private var savedScrollIndicatorInsets: UIEdgeInsets?
    /// A transcript pushed while the menu was up, applied once it closes (so an arriving message can't
    /// reflow the content mid-preview). Mirrors ChatLayout deferring updates while `.showingPreview`.
    private var deferredItems: [ChatItem]?
    /// A bottom inset requested while the menu had the inset frozen, applied once it closes. The bar
    /// can grow from a menu action (choosing Edit opens the editing banner); without holding the
    /// request the transcript keeps the old bar's inset until some later layout pass corrects it.
    private var pendingBottomInset: CGFloat?

    /// Fired when a bubble that can take a reaction is double-tapped, to present the strip on its own.
    var onBubbleDoubleTap: ((ChatMessage) -> Void)?
    private weak var bubbleDoubleTap: UITapGestureRecognizer?
    /// Fired when a message's row is long-pressed, to lift it with its menu and reaction strip.
    var onBubbleLongPress: ((ChatMessage, _ press: CGPoint) -> Void)?
    /// Fired as the finger that long-pressed a row moves, with its point in window coordinates and
    /// whether it has just lifted, so the menu can follow it.
    var onBubbleLongPressTrack: ((CGPoint, _ ended: Bool) -> Void)?
    private weak var bubbleLongPress: UILongPressGestureRecognizer?
    /// The row's own bubble, hidden while a lifted copy stands in for it.
    private weak var hiddenLiftSource: UIView?

    /// Work handed over by a menu action to run, in order, once the lift has landed, so an action
    /// that raises the keyboard or reflows the transcript waits until the bubble is back in its row.
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
        // Double-tapping a bubble presents the reaction strip on its own. It only receives touches
        // that land on a bubble that can take one (see `doubleTapTarget(at:)`), so the keyboard's
        // tap waits on it there and nowhere else: lowering the keyboard between the two taps would
        // reflow the transcript and move the second tap onto another row.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(bubbleDoubleTapped))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delaysTouchesEnded = false
        doubleTap.delegate = self
        collectionView.addGestureRecognizer(doubleTap)
        dismissKeyboardTap.require(toFail: doubleTap)
        bubbleDoubleTap = doubleTap
        // Long-pressing a row lifts it with its menu. It only receives touches on a row that has a
        // message (see `longPressTarget(at:)`), and it keeps tracking after it fires so a drag can
        // choose a menu row.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(bubbleLongPressed))
        longPress.minimumPressDuration = 0.35
        longPress.delegate = self
        collectionView.addGestureRecognizer(longPress)
        bubbleLongPress = longPress
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
        collectionView.register(ChatShareProfileCell.self, forCellWithReuseIdentifier: ChatShareProfileCell.reuseIdentifier)
        collectionView.register(ChatMediaCell.self, forCellWithReuseIdentifier: ChatMediaCell.reuseIdentifier)
        collectionView.register(ChatDateSeparatorCell.self, forCellWithReuseIdentifier: ChatDateSeparatorCell.reuseIdentifier)
        collectionView.register(ChatUnreadDividerCell.self, forCellWithReuseIdentifier: ChatUnreadDividerCell.reuseIdentifier)
        collectionView.register(ChatEncryptionMarkerCell.self, forCellWithReuseIdentifier: ChatEncryptionMarkerCell.reuseIdentifier)
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
        if let frozenBottomInset, !isAdjustingBottomInset {
            holdBottomInset(at: frozenBottomInset)
            return
        }
        // The system changed the adjusted inset — on-device this is the keyboard showing or hiding.
        // If the user was at the bottom, follow it so the newest message stays just above the
        // keyboard; a reader who scrolled up is left where they are.
        //
        // While a context menu is up the bottom inset is held (`holdBottomInset`) above; handing it back
        // on close fires this once more, and following that would move the content the hold kept still.
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
        appendedFrom = Self.appendStart(from: items, to: newItems)
        appendedRise = nil
        let handoff = handOffTypingBubble(from: items, to: newItems)
        growingFromTyping = handoff?.row
        // `performBatchUpdates` inherits the enclosing animation's timing, which is the only way to
        // give ChatLayout's insertion a spring: the layout delegate below supplies the *starting*
        // state, this supplies the curve it travels on.
        let spring = handoff == nil ? Self.batchSpring(for: changeset) : ChatMotion.fromTyping
        spring.animate { [self] in
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
                    appendedFrom = nil
                    appendedRise = nil
                    growingFromTyping = nil
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
        // After the batch rather than inside it: the arriving cell exists now, laid out where it
        // lands, and the grow is its own Core Animation rather than a passenger on the batch's spring.
        if let handoff, let cell = collectionView.cellForItem(at: IndexPath(item: handoff.row, section: 0)) as? ChatColumnCell {
            cell.grow(
                from: handoff.typing,
                on: spring,
                textDelay: ChatMotion.fromTypingTextDelay,
                textFade: ChatMotion.fromTypingTextFade,
                remnantFade: ChatMotion.fromTypingDotsFade
            )
        }
    }

    /// Hands the typing bubble to the incoming message replacing it in this update, returning the
    /// message's row and what the bubble handed over, or nil when the update is not that handoff or
    /// the dots are not on screen to hand anything over.
    private func handOffTypingBubble(from old: [ChatItem], to new: [ChatItem]) -> (row: Int, typing: ChatTypingHandoff)? {
        guard let row = Self.typingHandoffRow(from: old, to: new),
              let message = message(at: row, in: new),
              let cell = collectionView.cellForItem(at: IndexPath(item: old.count - 1, section: 0)) as? ChatTypingIndicatorCell
        else { return nil }
        // The face the message will draw beside its bubble, which the dots' stack hands over.
        let face = message.isContinuationFromPrevious ? nil : message.author?.id
        return cell.handOff(keepingFaceOf: face).map { (row, $0) }
    }

    /// The row of the incoming message that takes the typing bubble's place in an update from `old`
    /// to `new`, or nil when there is none. The rows appended at the bottom are the arrivals, and
    /// `TypingDotsHandoff` picks among them against who was typing before and after.
    static func typingHandoffRow(from old: [ChatItem], to new: [ChatItem]) -> Int? {
        guard let trailing = old.last, let typingBefore = typing(in: trailing),
              let start = appendStart(from: old, to: new)
        else { return nil }
        let typingAfter = new.lazy.compactMap(typing(in:)).first ?? []
        let arrivals = (start..<new.count).compactMap { row -> (row: Int, message: ChatMessage)? in
            switch new[row] {
            case .message(let message): (row, message)
            case .typingIndicator, .dateSeparator, .unreadDivider, .profileCard, .groupCard, .encryptionMarker: nil
            }
        }
        guard let taker = TypingDotsHandoff.takerIndex(
            typingBefore: typingBefore,
            arrivals: arrivals.map { speaker(of: $0.message) },
            typingAfter: typingAfter
        ) else { return nil }
        let (row, message) = arrivals[taker]
        // The grow is drawn for one bubble, so a message split around its link card inserts normally.
        guard row == new.count - 1, message.part == nil else { return nil }
        return row
    }

    /// Who a row speaks for, as the handoff compares senders with typists. A DM's dots and its
    /// incoming rows carry no author, so both stand for the one counterpart.
    private enum Speaker: Hashable {
        case viewer
        case counterpart
        case member(UserID)
    }

    /// Who the typing indicator shows as typing, or nil when `item` is not the typing indicator.
    private static func typing(in item: ChatItem) -> Set<Speaker>? {
        switch item {
        case .typingIndicator(let typists):
            typists.isEmpty ? [.counterpart] : Set(typists.map { .member($0.id) })
        case .message, .dateSeparator, .unreadDivider, .profileCard, .groupCard, .encryptionMarker:
            nil
        }
    }

    private static func speaker(of message: ChatMessage) -> Speaker {
        switch message.sender {
        case .me:    .viewer
        case .other: message.author.map { .member($0.id) } ?? .counterpart
        }
    }

    private func message(at index: Int, in items: [ChatItem]) -> ChatMessage? {
        guard items.indices.contains(index) else { return nil }
        switch items[index] {
        case .message(let message): return message
        case .typingIndicator, .dateSeparator, .unreadDivider, .profileCard, .groupCard, .encryptionMarker: return nil
        }
    }

    /// The spring a batch update travels on: `insertion` when rows arrive, leave or move, `reflow`
    /// when the diff only reconfigures rows already in place.
    ///
    /// A reconfigure changes a row's height at most (a receipt moving, a status resolving, an
    /// edit), and the arrival spring's bounce would lurch the whole transcript for it.
    static func batchSpring(for changeset: StagedChangeset<[ChatItem]>) -> ChatSpring {
        let changesRows = changeset.contains { stage in
            !stage.elementInserted.isEmpty
                || !stage.elementDeleted.isEmpty
                || !stage.elementMoved.isEmpty
                || stage.sectionChangeCount > 0
        }
        return changesRows ? ChatMotion.insertion : ChatMotion.reflow
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
            let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : UIScreen.main.bounds.width
            (cell as! ChatGroupCardCell).configure(
                with: card,
                inviteCardWidth: width * Self.maxBubbleWidthFraction,
                onTap: cardTap,
                onInvite: invite
            )
        case .dateSeparator(_, let text):
            (cell as! ChatDateSeparatorCell).configure(text: text)
        case .unreadDivider(let count):
            (cell as! ChatUnreadDividerCell).configure(count: count)
        case .encryptionMarker:
            let tap: (() -> Void)? = onEncryptionMarkerTap == nil ? nil : { [weak self] in self?.onEncryptionMarkerTap?() }
            (cell as! ChatEncryptionMarkerCell).configure(onTap: tap)
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
        // Text and photo messages are sent optimistically, so only they can reach the failed state
        // that arms retry. Cash messages are always server-confirmed.
        case let cell as ChatLinkMessageCell:
            // Before `configure`, which is where the card subscribes.
            cell.linkCardSource = linkCardSource
            cell.configure(
                with: message,
                maxWidth: maxWidth,
                authorImageData: authorImageData,
                quoteThumbnail: quoteThumbnail(for: message)
            )
            cell.onRetry = { [weak self] id in self?.onRetry?(id) }
            cell.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
            cell.onMentionTap = { [weak self] username in self?.onMentionTap?(username) }
            cell.onLinkCardTap = { [weak self] card in self?.onLinkCardTap?(card, message.messageID) }
            cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
            cell.onReactionTap = { [weak self] emoji in self?.onReactionTap?(message.messageID, emoji) }
            cell.onReactionLongPress = { [weak self] emoji in self?.onReactionLongPress?(message.messageID, emoji) }
            cell.onReactionAdd = { [weak self] in self?.onReactionAdd?(message.messageID) }
        case let cell as ChatMessageCell:
            cell.configure(
                with: message,
                maxWidth: maxWidth,
                authorImageData: authorImageData,
                quoteThumbnail: quoteThumbnail(for: message)
            )
            cell.onRetry = { [weak self] id in self?.onRetry?(id) }
            cell.onQuoteTap = { [weak self] id in self?.onQuoteTap?(id) }
            cell.onReactionTap = { [weak self] emoji in self?.onReactionTap?(message.messageID, emoji) }
            cell.onReactionLongPress = { [weak self] emoji in self?.onReactionLongPress?(message.messageID, emoji) }
            cell.onReactionAdd = { [weak self] in self?.onReactionAdd?(message.messageID) }
        case let cell as ChatCashCardCell:
            let cardWidth = (available - ChatColumnCell.rowInset * 2) * Self.cashCardWidthFraction
            cell.configure(with: message, maxWidth: cardWidth, authorImageData: authorImageData)
            cell.onReactionTap = { [weak self] emoji in self?.onReactionTap?(message.messageID, emoji) }
            cell.onReactionLongPress = { [weak self] emoji in self?.onReactionLongPress?(message.messageID, emoji) }
            cell.onReactionAdd = { [weak self] in self?.onReactionAdd?(message.messageID) }
        case let cell as ChatShareProfileCell:
            cell.linkCardSource = linkCardSource
            cell.ownProfile = ownProfile
            cell.onShare = { [weak self] card, name in self?.onShareProfile?(card, name) }
            let cardWidth = available - ChatColumnCell.rowInset * 2
            cell.configure(with: message, maxWidth: cardWidth, authorImageData: authorImageData)
            cell.onReactionTap = { [weak self] emoji in self?.onReactionTap?(message.messageID, emoji) }
            cell.onReactionLongPress = { [weak self] emoji in self?.onReactionLongPress?(message.messageID, emoji) }
            cell.onReactionAdd = { [weak self] in self?.onReactionAdd?(message.messageID) }
        case let cell as ChatMediaCell:
            guard case .media(let media) = message.content else { return }
            let remote = mediaURLResolver?.location(for: media, canReact: message.canReact) { [weak self] _ in
                self?.reconfigureVisibleMessage(id: message.id)
            }
            let localImage = pendingMediaImage?(message.id)
            cell.configure(
                with: message,
                maxWidth: maxWidth,
                localImage: localImage,
                progress: pendingMediaProgress?(message.id),
                remote: remote,
                authorImageData: authorImageData
            )
            cell.onImageTap = { [weak self, weak cell] in
                guard let self, let request = ChatMediaViewerRequest(
                    message: message,
                    localImage: localImage,
                    remote: remote,
                    placeholder: cell?.imageView.image,
                    sourceView: { [weak self] in self?.mediaSourceView(forMessageID: message.id) }
                ) else { return }
                onMediaTap?(request)
            }
            cell.onRetry = { [weak self] id in self?.onRetry?(id) }
            cell.onReactionTap = { [weak self] emoji in self?.onReactionTap?(message.messageID, emoji) }
            cell.onReactionLongPress = { [weak self] emoji in self?.onReactionLongPress?(message.messageID, emoji) }
            cell.onReactionAdd = { [weak self] in self?.onReactionAdd?(message.messageID) }
        default:
            assertionFailure("Unhandled chat cell class for message row")
        }
    }

    /// Where a reply's quoted photo draws its thumbnail from, or nil when it has none or is not yet
    /// resolved; a resolution redraws the reply.
    private func quoteThumbnail(for message: ChatMessage) -> ChatMediaLocation? {
        guard let quote = message.quote else { return nil }
        return mediaURLResolver?.thumbnailLocation(for: quote.kind, canReact: message.canReact) { [weak self] _ in
            self?.reconfigureVisibleMessage(id: message.id)
        }
    }

    /// Re-runs `configure` on the on-screen row for `id`, if there is one. A row off screen picks the
    /// change up on its next dequeue.
    private func reconfigureVisibleMessage(id: String) {
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  items.indices.contains(indexPath.item),
                  case .message(let message) = items[indexPath.item],
                  message.id == id else { continue }
            configure(cell, with: message)
        }
    }

    /// The on-screen photo of the row for `id`, or nil when that row is scrolled away.
    private func mediaSourceView(forMessageID id: String) -> UIView? {
        guard let index = items.firstIndex(where: { item in
            if case .message(let message) = item { message.id == id } else { false }
        }) else { return nil }
        return (collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ChatMediaCell)?.imageView
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

    // MARK: - Lift gestures

    @objc private func bubbleLongPressed(_ press: UILongPressGestureRecognizer) {
        switch press.state {
        case .began:
            guard let message = longPressTarget(at: press.location(in: collectionView)) else { return }
            onBubbleLongPress?(message, press.location(in: nil))
        case .changed:
            onBubbleLongPressTrack?(press.location(in: nil), false)
        case .ended:
            onBubbleLongPressTrack?(press.location(in: nil), true)
        case .possible, .cancelled, .failed:
            break
        @unknown default:
            break
        }
    }

    /// The message whose row is at `point` if a long press there should lift it. The reaction row
    /// keeps its own long press, which opens the reactors sheet.
    private func longPressTarget(at point: CGPoint) -> ChatMessage? {
        guard !isUpdating, !isShowingContextMenu,
              let indexPath = collectionView.indexPathForItem(at: point),
              let message = message(at: indexPath),
              collectionView.cellForItem(at: indexPath) is BubbleCarrying,
              !isInReactionRow(point) else { return nil }
        return message
    }

    @objc private func bubbleDoubleTapped(_ tap: UITapGestureRecognizer) {
        guard let message = doubleTapTarget(at: tap.location(in: collectionView)) else { return }
        onBubbleDoubleTap?(message)
    }

    /// The message whose bubble is at `point` if a double tap there should present the reaction
    /// strip. Only text bubbles take one: link cards, cash cards, quote panels and reaction pills
    /// keep their instant single tap.
    private func doubleTapTarget(at point: CGPoint) -> ChatMessage? {
        guard !isUpdating, !isShowingContextMenu,
              let indexPath = collectionView.indexPathForItem(at: point),
              let message = message(at: indexPath),
              message.offersReactionStrip, !message.rendersAsBareLinkCard,
              let cell = collectionView.cellForItem(at: indexPath) as? BubbleCarrying else { return nil }
        switch message.content {
        case .text: break
        case .cash, .deleted, .unavailable, .shareProfile, .media: return nil
        }
        let bubble = cell.liftPreviewView
        guard bubble.bounds.contains(bubble.convert(point, from: collectionView)) else { return nil }
        var view = collectionView.hitTest(point, with: nil)
        while let current = view, current !== bubble {
            if current is ReactionPillRowView || current is ChatQuotePanelView || current is LinkCardView { return nil }
            view = current.superview
        }
        return message
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
        let target = inset + Self.bottomContentPadding
        guard isViewLoaded, abs(collectionView.contentInset.bottom - target) > 0.5 else { return }
        // A send that collapses a multiline draft lands the bar's new height inside the insert's
        // batch update. The snapshot re-anchor below can't run there — it reads ChatLayout's
        // mid-update attributes and forces a layout pass, which is what made an append overshoot —
        // and holding the inset for the update's completion left the transcript a whole beat behind
        // the bar, then snapped it.
        guard !isUpdating else {
            followBottomInset(to: target)
            return
        }
        let snapshot = chatLayout.getContentOffsetSnapshot(from: .bottom)
        isAdjustingBottomInset = true // suppress the delegate re-entry from the inset write below
        collectionView.contentInset.bottom = target
        collectionView.verticalScrollIndicatorInsets.bottom = target
        isAdjustingBottomInset = false
        if let snapshot {
            chatLayout.restoreContentOffset(with: snapshot)
        }
    }

    /// Moves the bottom inset to `target` while a batch update is in flight, carrying the content
    /// by the same amount on `keyboardScroll`: the same result the snapshot re-anchor gives, since
    /// the edge the transcript is anchored to moved by exactly that much, worked out from the
    /// scroll view's own numbers so no layout pass is forced mid-update.
    private func followBottomInset(to target: CGFloat) {
        let change = target - collectionView.contentInset.bottom
        let from = collectionView.contentOffset
        isAdjustingBottomInset = true
        collectionView.contentInset.bottom = target
        collectionView.verticalScrollIndicatorInsets.bottom = target
        // A shrinking inset clamps the offset into the new range there and then, which is the snap
        // this is here to avoid; the glide below starts from where the content really was.
        collectionView.contentOffset = from
        isAdjustingBottomInset = false
        let top = -collectionView.adjustedContentInset.top
        let bottom = chatLayout.collectionViewContentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        let offset = min(max(from.y + change, top), max(bottom, top))
        guard abs(offset - from.y) > 0.5 else { return }
        ChatMotion.keyboardScroll.animate {
            self.collectionView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }
    }

    /// Whether the transcript sits at its newest message, within a point, on the scroll view's
    /// resting geometry. Content shorter than the viewport always does.
    public var isAtBottom: Bool {
        guard isViewLoaded else { return true }
        let top = -collectionView.adjustedContentInset.top
        let bottom = chatLayout.collectionViewContentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        return max(bottom, top) - collectionView.contentOffset.y <= 1
    }

    /// Holds the adjusted bottom inset at its current (keyboard-up) value for the menu's lifetime, so
    /// the keyboard leaving under the menu can't shrink it — the keyboard's space stays reserved and
    /// the content holds its exact position.
    ///
    /// The adjustment behavior stays `.always`: switching the transcript to `.never` changes how UIKit
    /// hands the safe area down to its rows, and a SwiftUI-hosted card sitting under the navigation bar
    /// re-lays its content for it — the card jumped onto its own reaction pills on every long press.
    private func freezeInset() {
        guard frozenBottomInset == nil else { return }
        frozenBottomInset = collectionView.adjustedContentInset.bottom
        savedContentInset = collectionView.contentInset
        savedScrollIndicatorInsets = collectionView.verticalScrollIndicatorInsets
    }

    /// Re-sizes the content inset so the system's share plus ours still adds up to `bottom`. Runs from
    /// the adjusted-inset callback, before the scroll view lays out, so a transcript sitting at its
    /// bottom never sees the shrunken range and has nothing to clamp.
    private func holdBottomInset(at bottom: CGFloat) {
        let system = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let own = max(0, bottom - system)
        guard abs(collectionView.contentInset.bottom - own) > 0.5 else { return }
        isAdjustingBottomInset = true
        collectionView.contentInset.bottom = own
        collectionView.verticalScrollIndicatorInsets.bottom = own
        isAdjustingBottomInset = false
    }

    /// Hands the bottom inset back to the system, which re-derives it from wherever the keyboard is by
    /// then: back up behind the menu, in which case nothing moves, or gone, in which case the
    /// transcript settles into the space it vacated.
    private func restoreInset() {
        guard frozenBottomInset != nil else { return }
        frozenBottomInset = nil
        if let inset = savedContentInset { collectionView.contentInset = inset }
        if let indicator = savedScrollIndicatorInsets { collectionView.verticalScrollIndicatorInsets = indicator }
        savedContentInset = nil
        savedScrollIndicatorInsets = nil
        // No `restoreContentOffset` re-anchor: forcing ChatLayout's layout pass during the
        // context-menu keyboard transition aborts on iOS 26 (a UICollectionView bounds-change
        // "fading" assertion). The at-bottom follow in `scrollViewDidChangeAdjustedContentInset`
        // settles the position through the normal path once the menu flag is cleared.
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
        // Its cell plays the arrival instead: the chrome grows out of the dots in the slot it lands in.
        guard indexPath.item != growingFromTyping else { return }
        switch state {
        case .initial:
            ChatMotion.applyInsertionState(
                to: originalAttributes,
                sender: sender(at: indexPath),
                rise: insertionRise(for: indexPath, frame: originalAttributes.frame)
            )
        case .invalidation:
            // Still the same arrival — ChatLayout only asks this for an inserted row, once
            // self-sizing has resolved its real height. It overwrites the frame first, so the
            // starting state has to be re-stated rather than assumed to have survived. The rise is
            // re-measured too, since the real height changes the room the block makes.
            if indexPath.item == appendedFrom { appendedRise = nil }
            ChatMotion.applyInsertionState(
                to: originalAttributes,
                sender: sender(at: indexPath),
                rise: insertionRise(for: indexPath, frame: originalAttributes.frame)
            )
        }
    }

    /// How far below its slot an inserted row starts: the room the appended block makes (its height
    /// plus the gap above it), so it rides up with the rows it pushes. Zero for a row inserted
    /// anywhere but the bottom, which pushes nothing up.
    private func insertionRise(for indexPath: IndexPath, frame: CGRect) -> CGFloat {
        guard let start = appendedFrom, indexPath.item >= start else { return 0 }
        if let appendedRise { return appendedRise }
        let gap = start > 0
            ? interItemSpacing(chatLayout, after: IndexPath(item: start - 1, section: indexPath.section)) ?? RowGap.normal
            : 0
        // Measured from the block's first row to the bottom of the content. Asked for any later row
        // first, the row's own height is the best estimate until the first row is measured.
        let block = indexPath.item == start
            ? chatLayout.collectionViewContentSize.height - frame.minY
            : frame.height
        let rise = min(max(block, frame.height) + gap, collectionView.bounds.height) * ChatMotion.insertionRise
        if indexPath.item == start { appendedRise = rise }
        return rise
    }

    /// The index where the block of rows appended at the bottom begins, or nil when the update adds
    /// nothing there. Rows are matched by diff identity, so a row that only changed stays put.
    static func appendStart(from old: [ChatItem], to new: [ChatItem]) -> Int? {
        let known = Set(old.map(\.differenceIdentifier))
        var start = new.count
        while start > 0, !known.contains(new[start - 1].differenceIdentifier) { start -= 1 }
        return start < new.count && start > 0 ? start : nil
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
        case .dateSeparator, .unreadDivider, .encryptionMarker: return true
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
        case .dateSeparator, .unreadDivider, .profileCard, .groupCard, .encryptionMarker: return nil
        }
    }
}

extension ChatViewController: UIGestureRecognizerDelegate {
    /// Keeps the double tap to bubbles that present the reaction strip, so a tap anywhere else lowers
    /// the keyboard without waiting on it, and the long press to rows that can lift.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === bubbleDoubleTap {
            return doubleTapTarget(at: touch.location(in: collectionView)) != nil
        }
        if gestureRecognizer === bubbleLongPress {
            return longPressTarget(at: touch.location(in: collectionView)) != nil
        }
        return true
    }

    /// Lets the tap-to-dismiss recognizer fire alongside the collection view's own scroll and
    /// selection recognizers, so lowering the keyboard never pre-empts a cell tap.
    ///
    /// Swipe-to-reply is the exception: it translates a cell, so running it beside the scroll would
    /// drag a row sideways mid-scroll, and running it beside the long-press would slide the row out
    /// from under its own lift. It is exclusive in both directions. So is the long press, against
    /// everything: once it lifts a row, the taps under the finger must fail rather than fire on
    /// release, and the scroll must not move the transcript under the lift.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let exclusive: [UIGestureRecognizer?] = [swipeToReply.recognizer, bubbleLongPress]
        return !exclusive.contains { $0 === gestureRecognizer || $0 === otherGestureRecognizer }
    }
}

// MARK: - Message menu

extension ChatViewController {

    /// The actions a row offers, in the order the mapper put them in, or `nil` if it offers none.
    /// Rows with no actions — cash cards, tombstones, date separators — opt out.
    func contextMenu(forItemAt indexPath: IndexPath) -> UIMenu? {
        guard let message = message(at: indexPath) else { return nil }
        return contextMenu(for: message)
    }

    /// The actions `message` offers, or `nil` if it offers none.
    func contextMenu(for message: ChatMessage) -> UIMenu? {
        guard !message.actions.isEmpty else { return nil }

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

    private func isInReactionRow(_ point: CGPoint) -> Bool {
        var view = collectionView.hitTest(point, with: nil)
        while let current = view {
            if current is ReactionPillRowView { return true }
            view = current.superview
        }
        return false
    }

    /// Hands the transcript back once a lift has landed: shows the row's bubble again, releases the
    /// inset, and applies whatever was held while the lift was up.
    private func resumeAfterLift() {
        hiddenLiftSource?.alpha = 1
        hiddenLiftSource = nil
        // Restore the inset while the flag is still set, so the behavior switch's inset change is
        // suppressed (no stray scroll); then drop the flag and apply any held update.
        restoreInset()
        isShowingContextMenu = false
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

    /// Lifts the row drawing `message` out of the transcript. Holds the transcript still and hides
    /// the row's bubble; returns a raised copy of the bubble and where the bubble sits in `space`.
    /// Nil when the row is off screen or a lift or update already holds the transcript. End it with
    /// `endLift()`.
    func beginLift(for message: ChatMessage, in space: UICoordinateSpace) -> (copy: UIView, frame: CGRect)? {
        guard !isShowingContextMenu, !isUpdating,
              let item = items.firstIndex(where: { $0.id == message.id }),
              let cell = collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? BubbleCarrying,
              let copy = liftCopy(of: cell) else { return nil }
        isShowingContextMenu = true
        freezeInset()
        let bubble = cell.liftPreviewView
        let frame = space.convert(bubble.bounds, from: bubble)
        hideLiftSource(bubble)
        return (copy, frame)
    }

    /// Where the lifted row's bubble sits now, in `space`'s coordinates, or `nil` when no lift is up
    /// or its row has left the screen. A lift lands here rather than where it started.
    func liftSourceFrame(in space: UICoordinateSpace) -> CGRect? {
        guard isShowingContextMenu, let bubble = hiddenLiftSource, bubble.window != nil else { return nil }
        return space.convert(bubble.bounds, from: bubble)
    }

    /// The view a landing copy flies inside, and where the lifted row's bubble sits in it; `nil` when
    /// no lift is up or its row has left the screen.
    func liftLanding() -> (container: UIView, frame: CGRect)? {
        liftSourceFrame(in: collectionView).map { (collectionView, $0) }
    }

    /// Ends a lift once its copy is back over the row.
    func endLift() {
        guard isShowingContextMenu else { return }
        resumeAfterLift()
    }

    /// A raised copy of `cell`'s bubble.
    private func liftCopy(of cell: BubbleCarrying) -> UIView? {
        let bubble = cell.liftPreviewView
        // A bubble that hasn't rendered a frame yet has nothing to copy without the pending update.
        guard !bubble.bounds.isEmpty,
              let copy = bubble.snapshotView(afterScreenUpdates: false) ?? bubble.snapshotView(afterScreenUpdates: true) else { return nil }
        BubbleBackgroundView.raise(copy, shape: cell.liftPreviewMaskingPath)
        return copy
    }

    private func hideLiftSource(_ bubble: UIView) {
        if hiddenLiftSource !== bubble { hiddenLiftSource?.alpha = 1 }
        hiddenLiftSource = bubble
        // Alpha, not `isHidden`: a hidden arranged subview collapses the row's stack.
        bubble.alpha = 0
    }

    /// Run `work` once no lift is on screen — immediately if none is up, otherwise after the
    /// current one has landed.
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
        // The row's own bubble is hidden for as long as a lift is on screen and shown again as it
        // lands. Snapshotting in that window returns a view that is blank rather than nil, which
        // would float an empty copy and never be retried — so report "not yet" and let the caller
        // ask again.
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
