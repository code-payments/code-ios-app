//
//  ChatScreenViewController.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The full chat screen, entirely in UIKit: the transcript fills the view and one injected bar
/// floats over its bottom (so content flows under it). `KeyboardFloor` holds the bar at the bottom
/// safe area when the keyboard is down and on the keyboard's top edge when it is up — one bar
/// covers both states. This screen stays agnostic about *what* the bar is and only owns layout +
/// keyboard handling.
///
/// The transcript reserves only the bar's own height. The system already grows the collection
/// view's content inset by the keyboard, so counting the keyboard here too overscrolls the
/// transcript by a whole keyboard.
public final class ChatScreenViewController: UIViewController {

    private let transcript = ChatViewController()
    private let bar: UIView
    private let barController: UIViewController?
    /// The box the bar is seen through: the bar sits at its *bottom* edge and is clipped by it.
    ///
    /// The reply strip is the reason there are two views rather than one. The bar's own height has
    /// to be its content's height exactly, and that height jumps the moment the strip mounts; the
    /// visible box has to travel to the same number over the strip's spring. Those are different
    /// numbers at the same instant, and a single view cannot hold both — animating one view's height
    /// leaves its hosted SwiftUI content laid out for the destination while the layer is still on the
    /// way there, and the content is drawn off its mark by the whole difference. Measured on a 60fps
    /// capture, that put the composer row 24pt — half the strip's 48 — from where it belongs. Pinned
    /// to the bottom of a box that clips it, the bar's frame can jump to the strip's full height
    /// while the box uncovers it, and the composer row does not move at all.
    private let barClip = BarClipView()
    /// Carries the chat background on below the fade, so the keyboard has that behind it rather
    /// than the transcript.
    ///
    /// The keyboard's top corners are rounded, and what shows through them is whatever the app draws
    /// behind the keyboard. That is the transcript, which reaches the bottom of the screen — so a
    /// bubble scrolled under the bar left a hard-edged wedge of itself at each bottom corner of the
    /// bar, about 24×25pt on an iPhone 16 Pro, invisible against a dark bubble and obvious behind a
    /// photo avatar. The bar cannot fill them itself: it sits on ``barClip``'s bottom edge and the
    /// clip cuts everything below it.
    ///
    /// Tied to the fade's bottom — the keyboard's top edge — rather than given a height, so it is
    /// exactly the keyboard's region: the whole keyboard when one is up, nothing at all when it is
    /// down. Nothing else can see it: every point it covers is a point the keyboard is covering.
    private let keyboardCornerCover = UIView()
    /// The clip's height — what the screen and the transcript actually see as the bar. Driven by the
    /// bar's *measured* SwiftUI height, minus a card that is on its way out.
    /// The clip height the transcript reserves room for while the clip is held taller than the glass
    /// during an in-place resize; `nil` when it reserves the clip's own height.
    private var transcriptCover: CGFloat?
    /// Holds the fade's top edge on the transcript's while the clip is held above it, so the
    /// ramp's dark end never lands on the bubble the transcript just moved down.
    private var fadeTopConstraint: NSLayoutConstraint!
    private var barClipHeightConstraint: NSLayoutConstraint!

    /// Whether the bar draws and takes touches above its own frame, for a panel it floats over the
    /// transcript. While set, the bar's view reaches the top of the screen with its content still on
    /// its bottom edge, the clip stops cutting it, and the transcript's inset is left alone.
    public var barOverflowsTop = false {
        didSet {
            guard barOverflowsTop != oldValue, barClipHeightConstraint != nil else { return }
            // The bar is already as tall as the screen and pinned to the clip's bottom, so letting
            // it draw and take touches above the clip is all the overflow needs.
            barClip.clipsToBounds = !barOverflowsTop
            barClip.overflowTarget = barOverflowsTop ? bar : nil
        }
    }
    /// Where, in window coordinates, the bar starts taking touches while it overflows, or `nil` for
    /// everywhere it reaches. A card standing over the transcript takes touches on itself and lets the
    /// rest through; a panel that dismisses on any outside touch takes them all.
    public var barOverflowTouchTop: CGFloat? {
        didSet { barClip.overflowTouchTop = barOverflowTouchTop }
    }

    /// Keeps the bar above the keyboard. Not `view.keyboardLayoutGuide`: see `KeyboardFloor`.
    private var keyboardFloor: KeyboardFloor!

    /// Raise the keyboard once the screen has finished appearing (post-tip open). Driven from
    /// UIKit rather than a SwiftUI `@FocusState`: a hosted composer's programmatic focus updates
    /// SwiftUI's focus state but never presents the keyboard across the hosting boundary — only a
    /// real `becomeFirstResponder` does.
    public var focusesComposerOnAppear = false

    /// Whether the transcript is blurred out and frozen, because the chat's listener rules are
    /// unmet. The bar is left sharp and keeps its own height, so the gate panel the caller hosts in
    /// place of the composer measures and reserves transcript inset exactly as the composer does.
    public var isTranscriptObscured = false {
        didSet { transcriptBlur.isShown = isTranscriptObscured }
    }

    /// Whether to draw the gate's decorative shapes behind the blur — set when the chat is
    /// obscured and there is nothing real under it. See ``GatePreviewPlaceholder``.
    public var showsGatePlaceholder = false {
        didSet { gatePlaceholder.isShown = showsGatePlaceholder }
    }
    private var didFocusComposer = false
    /// Whether the composer held the keyboard when the current context menu opened, and so should get
    /// it back when that menu goes. Cleared by `dismissKeyboard()` so an action handing off to a sheet
    /// isn't fought by the restore.
    private var composerHeldKeyboardUnderMenu = false
    /// The blur shown behind a context menu, and held past it for an edit.
    private let backdrop = MessageBackdrop()
    /// The blur over a transcript the user is not allowed to read. See `TranscriptBlur`.
    private let transcriptBlur = TranscriptBlur()
    /// The decorative shapes the blur softens when there is no transcript to soften. See
    /// `GatePreviewPlaceholder`.
    private let gatePlaceholder = GatePreviewPlaceholder()
    /// The row floated above a held blur, while an edit is open on it.
    private var editedStableID: String?
    /// Deferred attempts left at floating the edited message's copy. The menu's dismissal
    /// completion lands while UIKit is still putting the row's own bubble back, so the first
    /// attempt usually has nothing to copy; retrying over the next few runloop turns catches it
    /// without waiting on a layout pass or a scroll that may never come.
    private var spotlightAttemptsRemaining = 0
    /// How many of those attempts a single edit gets.
    private static let spotlightAttempts = 8
    /// Whether a measured bar height has landed yet — the first one is applied without animation.
    private var didMeasureBar = false

    /// The cards the last measured bar height reported, so a card opening or closing is told apart
    /// from ordinary growth.
    private var barAccessories = BarAccessories()
    /// The bar's last measured height, which the transcript's room is taken against.
    private var measuredBarHeight: CGFloat = 0
    /// The last room reported through ``onMentionRoomChange``, so an unchanged one is not sent again.
    private var reportedMentionRoom: CGFloat?
    /// The pop gestures switched off for the length of an edit, kept so only those are switched back
    /// on and one that was already off stays off.
    private var suspendedPopGestures: [UIGestureRecognizer] = []
    /// The dissolve from the transcript into the bottom of the screen. See ``ComposerFadeView``.
    private let fade = ComposerFadeView()
    /// How much closer to the bar the newest message sits while the keyboard is up.
    private static let raisedTranscriptDrop: CGFloat = 8
    /// How far into the bottom safe area the bar rests while the keyboard is down. Moves on the
    /// reply strip's spring when it changes on screen.
    public var barRestingDrop: CGFloat = 0 {
        didSet {
            guard barRestingDrop != oldValue, let keyboardFloor else { return }
            keyboardFloor.restingDrop = barRestingDrop
            guard view.window != nil, keyboardFloor.refresh() else { return }
            ChatMotion.replySurface.animate {
                self.view.layoutIfNeeded()
            }
        }
    }

    /// - Parameters:
    ///   - bar: pinned to the bottom of the view; rides the keyboard.
    ///   - barController: the view controller owning the bar, when hosted (e.g. a
    ///     `UIHostingController` for a SwiftUI bar). Adopted as a child so its lifecycle and
    ///     environment work. Pass `nil` for a plain `UIView` bar.
    public init(bar: UIView, barController: UIViewController? = nil) {
        self.bar = bar
        self.barController = barController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var onReachTop: (() -> Void)? {
        get { transcript.onReachTop }
        set { transcript.onReachTop = newValue }
    }

    public var onRetry: ((String) -> Void)? {
        get { transcript.onRetry }
        set { transcript.onRetry = newValue }
    }

    public var onCashCardTap: ((String) -> Void)? {
        get { transcript.onCashCardTap }
        set { transcript.onCashCardTap = newValue }
    }

    public var onOpenURL: ((URL) -> Void)? {
        get { transcript.onOpenURL }
        set { transcript.onOpenURL = newValue }
    }

    public var ownProfile: OwnProfileCard? {
        get { transcript.ownProfile }
        set { transcript.ownProfile = newValue }
    }

    public var onShareProfile: ((LinkCard.User, String?) -> Void)? {
        get { transcript.onShareProfile }
        set { transcript.onShareProfile = newValue }
    }

    public var onMentionTap: ((Username) -> Void)? {
        get { transcript.onMentionTap }
        set { transcript.onMentionTap = newValue }
    }

    public var onLinkCardTap: ((LinkCard, String) -> Void)? {
        get { transcript.onLinkCardTap }
        set { transcript.onLinkCardTap = newValue }
    }

    /// Fired when a photo in the transcript is tapped — see ``ChatViewController/onMediaTap``.
    public var onMediaTap: ((ChatMediaViewerRequest) -> Void)? {
        get { transcript.onMediaTap }
        set { transcript.onMediaTap = newValue }
    }

    /// Where a link card in the transcript looks its link up — see
    /// ``ChatViewController/linkCardSource``.
    public weak var linkCardSource: (any LinkCardSource)? {
        get { transcript.linkCardSource }
        set { transcript.linkCardSource = newValue }
    }

    /// Where a photo row gets its download URL — see ``ChatViewController/mediaURLResolver``.
    public var mediaURLResolver: ChatMediaURLResolver? {
        get { transcript.mediaURLResolver }
        set { transcript.mediaURLResolver = newValue }
    }

    /// A pending photo's local image — see ``ChatViewController/pendingMediaImage``.
    public var pendingMediaImage: ((String) -> UIImage?)? {
        get { transcript.pendingMediaImage }
        set { transcript.pendingMediaImage = newValue }
    }

    /// A pending photo's send progress — see ``ChatViewController/pendingMediaProgress``.
    public var pendingMediaProgress: ((String) -> ChatPhotoSendProgress?)? {
        get { transcript.pendingMediaProgress }
        set { transcript.pendingMediaProgress = newValue }
    }

    /// Avatar bytes for the transcript's authors, keyed by user id — see
    /// ``ChatViewController/authorAvatars``.
    public var authorAvatars: [UserID: Data] {
        get { transcript.authorAvatars }
        set { transcript.authorAvatars = newValue }
    }


    /// Forwards the "Encrypted" marker's tap from the transcript to the owner.
    public var onEncryptionMarkerTap: (() -> Void)? {
        get { transcript.onEncryptionMarkerTap }
        set { transcript.onEncryptionMarkerTap = newValue }
    }

    /// Forwards gutter-avatar taps from the transcript to the owner — see
    /// ``ChatViewController/onAuthorTap``.
    public var onAuthorTap: ((UserID) -> Void)? {
        get { transcript.onAuthorTap }
        set { transcript.onAuthorTap = newValue }
    }

    /// Called when the blur behind an open edit is tapped — WhatsApp's way out of an edit, beside
    /// the composer's own cancel button. The owner ends the edit, which brings the blur down.
    public var onCancelEdit: (() -> Void)?

    /// Forwards a chosen context-menu action, with the row's id, to whoever owns the screen.
    public var onMessageAction: ((String, MessageCapability) -> Void)? {
        get { transcript.onMessageAction }
        set { transcript.onMessageAction = newValue }
    }

    /// Forwards a tap on a reply's quote panel, with the quoted row's id.
    public var onQuoteTap: ((String) -> Void)? {
        get { transcript.onQuoteTap }
        set { transcript.onQuoteTap = newValue }
    }

    /// Forwards the newest message someone else sent that the reader has had on screen — see
    /// ``ChatViewController/onMessagesSeen``.
    public var onMessagesSeen: ((MessageID) -> Void)? {
        get { transcript.onMessagesSeen }
        set { transcript.onMessagesSeen = newValue }
    }

    /// Whether rows on screen count as read — see ``ChatViewController/reportsReads``.
    public var reportsReads: Bool {
        get { transcript.reportsReads }
        set { transcript.reportsReads = newValue }
    }

    /// Forwards a reaction-pill tap from the transcript, with the row's id and the toggled emoji.
    public var onReactionTap: ((String, String) -> Void)? {
        get { transcript.onReactionTap }
        set { transcript.onReactionTap = newValue }
    }

    /// Forwards a reaction-pill long-press from the transcript, with the row's id and emoji, to open
    /// the reactors sheet scoped to it.
    public var onReactionLongPress: ((String, String) -> Void)? {
        get { transcript.onReactionLongPress }
        set { transcript.onReactionLongPress = newValue }
    }

    /// Forwards a tap on a row's trailing "+" reaction pill, with the row's id, to open the picker.
    public var onReactionAdd: ((String) -> Void)? {
        get { transcript.onReactionAdd }
        set { transcript.onReactionAdd = newValue }
    }

    /// Supplies the long-press reaction strip's content for a message — recents plus the viewer's own
    /// reactions, per `ReactionStrip.entries`. The owner supplies this because the ranking source
    /// (`RecentReactionsStore`) lives above this module. Nil or an empty array suppresses the strip.
    public var reactionStripEntries: ((ChatMessage) -> [ReactionStrip.Entry])?

    /// Fired when an emoji in the long-press strip is tapped: the row's id and the toggled emoji.
    /// The strip dismisses the menu itself; this only needs to apply the toggle.
    public var onReactionStripSelect: ((String, String) -> Void)?

    /// Fired when the strip's trailing "+" is tapped, with the row's id, to open the picker once the
    /// menu has dismissed.
    public var onReactionStripAdd: ((String) -> Void)?

    /// The lift on screen, if any: its overlay and the message it raised.
    private var lift: (overlay: MessageLiftOverlay, message: ChatMessage)?
    /// The layer over the transcript that takes its touches, if one is up.
    private var transcriptShield: TranscriptShield?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Color.backgroundMain)

        addChild(transcript)
        transcript.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transcript.view)
        transcript.didMove(toParent: self)
        NSLayoutConstraint.activate([
            transcript.view.topAnchor.constraint(equalTo: view.topAnchor),
            transcript.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transcript.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transcript.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let constraints = addBar(bar, controller: barController)
        // Above the transcript and below the bar clip, so the gate panel naming the unmet
        // requirement stays sharp over the transcript it is talking about.
        transcriptBlur.install(in: view, below: barClip)
        // Under the blur, so the shapes are only ever seen through it.
        gatePlaceholder.install(in: view, below: transcriptBlur.view)

        barClipHeightConstraint = constraints.clipHeight
        keyboardFloor = KeyboardFloor(view: view, bottomConstraint: constraints.bottom, keyboardEdgeConstraint: constraints.keyboardEdge)
        keyboardFloor.restingDrop = barRestingDrop
        lowerComposerOnResignActive()
        backdrop.onTap = { [weak self] in self?.onCancelEdit?() }
        transcript.onScroll = { [weak self] in self?.refreshEditSpotlight() }
        transcript.onBubbleDoubleTap = { [weak self] message in self?.presentLift(for: message, withMenu: false) }
        transcript.onBubbleLongPress = { [weak self] message, press in self?.presentLift(for: message, withMenu: true, press: press) }
        transcript.onBubbleLongPressTrack = { [weak self] point, ended in
            guard let overlay = self?.lift?.overlay else { return }
            if ended {
                overlay.release(at: point)
            } else {
                overlay.track(point)
            }
        }
    }

    /// What the reaction strip offers for `message`, or `nil` when it offers none: the message can't
    /// take a reaction (see `ChatMessage.offersReactionStrip`), or the owner supplies no entries.
    private func stripEntries(for message: ChatMessage) -> [ReactionStrip.Entry]? {
        guard message.offersReactionStrip, let entries = reactionStripEntries?(message), !entries.isEmpty else { return nil }
        return entries
    }

    /// Lifts `message`'s bubble over a blur with its reaction strip above it and, for a long press,
    /// its action menu below it. A double tap brings up the strip alone, as iMessage does a tapback.
    /// The keyboard goes down for the lift and comes back when it ends. `press` is where a long
    /// press's finger landed (window coordinates), which may go on to drag onto a menu row.
    private func presentLift(for message: ChatMessage, withMenu: Bool, press: CGPoint? = nil) {
        guard lift == nil, let scene = view.window?.windowScene else { return }
        let entries = stripEntries(for: message)
        let actions = withMenu ? transcript.contextMenu(for: message)?.children.compactMap { $0 as? UIAction } : nil
        guard entries != nil || actions?.isEmpty == false,
              let (copy, frame) = transcript.beginLift(for: message, in: view) else { return }
        if withMenu {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        let overlay = MessageLiftOverlay()
        overlay.onStripSelect = { [weak self] emoji in
            self?.dismissLift()
            self?.onReactionStripSelect?(message.messageID, emoji)
        }
        overlay.onStripAdd = { [weak self] in
            self?.dismissLift()
            self?.onReactionStripAdd?(message.messageID)
        }
        // Performed as the lift starts down, as a system menu does: an action that needs the lift
        // gone (an edit's spotlight, a reply's focus) queues itself on `afterContextMenu`.
        overlay.onAction = { [weak self] action in
            self?.dismissLift()
            action.performWithSender(nil, target: nil)
        }
        overlay.onDismissRequest = { [weak self] in self?.dismissLift() }
        lift = (overlay, message)

        backdrop.present(over: contextMenuBackdropHost)
        if let responder = bar.firstTextInputResponder {
            composerHeldKeyboardUnderMenu = responder.isFirstResponder
            _ = responder.resignFirstResponder()
        }
        overlay.present(copy: copy, from: view.convert(frame, to: nil), in: scene, entries: entries, actions: actions, press: press)
    }

    /// Flies the lift back to where its row sits now, which a message pushed in while it was up may
    /// have moved, and hands the transcript and keyboard back.
    private func dismissLift() {
        guard let (overlay, _) = lift else { return }
        lift = nil
        let copy = overlay.dismiss(landingIn: transcript.liftLanding()) { [weak self] in
            self?.transcript.endLift()
        }
        backdrop.dismiss(revealing: copy)
        if composerHeldKeyboardUnderMenu {
            composerHeldKeyboardUnderMenu = false
            _ = bar.firstTextInputResponder?.becomeFirstResponder()
        }
    }

    /// Holds the context menu's blur into the edit it just opened, and floats the edited message
    /// above it — the message being edited ends up the one sharp thing above the composer, which is
    /// how WhatsApp presents an edit.
    ///
    /// Called from the menu action itself, which runs before the menu starts to dismiss, so the
    /// blur is claimed before the dismissal would have faded it: holding the one blur is what keeps
    /// the transcript from flashing back to legible between the menu and the edit. The floated copy
    /// waits for the menu to finish, because until then UIKit is still holding the row's own bubble
    /// as the lifted preview and the cell underneath is hidden.
    public func beginEditSpotlight(for stableID: String) {
        editedStableID = stableID
        backdrop.present(over: contextMenuBackdropHost)
        backdrop.hold(clearing: barClip, under: hostNavigationController?.navigationBar)
        setPopGesturesSuspended(true)
        transcript.afterContextMenu { [weak self] in
            self?.spotlightAttemptsRemaining = Self.spotlightAttempts
            self?.refreshEditSpotlight()
        }
    }

    /// Takes the blur down once the edit is over, however it ended.
    public func endEditSpotlight() {
        guard editedStableID != nil else { return }
        editedStableID = nil
        spotlightAttemptsRemaining = 0
        setPopGesturesSuspended(false)
        backdrop.release()
    }

    /// Ends an edit the screen is leaving in — a backstop for any way off this screen that isn't the
    /// edit's own. The blur and the floated copy are hosted by the navigation stack rather than by
    /// this screen, so they outlive a pop that leaves an edit open: they stay on whatever screen the
    /// pop lands on, taking its taps, with nothing left to dismiss them.
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissLift()
        endEditSpotlight()
    }

    /// Suspends swipe-to-go-back for the length of an edit, and puts back exactly what it suspended.
    ///
    /// An edit owns the whole screen — the blur takes every tap outside the message, and the composer
    /// is the only way out — so leaving the pop gesture live let a swipe carry the screen away from
    /// underneath it. A sheet-hosted stack carries a second pop recognizer alongside
    /// `interactivePopGestureRecognizer`, and it is the untouched twin that pops (see
    /// `EdgeOnlySwipeBack`), so every pop pan on the navigation view is suspended.
    private func setPopGesturesSuspended(_ suspended: Bool) {
        guard suspended else {
            suspendedPopGestures.forEach { $0.isEnabled = true }
            suspendedPopGestures = []
            return
        }
        guard suspendedPopGestures.isEmpty, let navigation = hostNavigationController else { return }
        let pops = (navigation.view.gestureRecognizers ?? [])
            .filter { $0 is UIPanGestureRecognizer && $0.isEnabled }
        pops.forEach { $0.isEnabled = false }
        suspendedPopGestures = pops
    }

    /// Puts the edited message's copy where its row now sits — floating it the first time, and
    /// re-framing it on every reflow after that, since the copy lives outside the transcript and
    /// doesn't follow the cell on its own. A row scrolled out of the transcript leaves the copy at
    /// its last frame rather than dropping it, so the message stays on screen for the whole edit.
    private func refreshEditSpotlight() {
        guard let editedStableID else { return }
        // Measured in the backdrop's own host, which is the navigation stack rather than this
        // screen whenever there is one to be in.
        if let frame = transcript.bubbleFrame(forStableID: editedStableID, in: contextMenuBackdropHost) {
            if backdrop.hasSpotlight {
                backdrop.moveSpotlight(to: frame)
            } else if let bubble = transcript.bubbleSnapshot(forStableID: editedStableID) {
                backdrop.setSpotlight(bubble, at: frame)
            }
        }
        guard !backdrop.hasSpotlight, spotlightAttemptsRemaining > 0 else { return }
        spotlightAttemptsRemaining -= 1
        Task { @MainActor [weak self] in self?.refreshEditSpotlight() }
    }

    /// The navigation stack this screen is inside, if any — the SwiftUI hosting controllers this
    /// screen is wrapped in sit between the two, so it is reached by walking the parent chain.
    private var hostNavigationController: UINavigationController? {
        var ancestor = parent
        while let current = ancestor {
            if let navigation = current as? UINavigationController { return navigation }
            ancestor = current.parent
        }
        return nil
    }

    /// The view the blur covers: the navigation stack when this screen is inside one, so the
    /// navigation bar goes soft with the transcript, and this screen's own view otherwise.
    private var contextMenuBackdropHost: UIView {
        hostNavigationController?.view ?? view
    }

    /// Adds a hosted bar sitting on the bottom edge of a clip box that spans the view's width;
    /// returns the clip's height constraint (driven later by the bar's measured SwiftUI content
    /// height) and the clip's bottom constraint (driven by the keyboard).
    private func addBar(
        _ bar: UIView,
        controller: UIViewController?
    ) -> (clipHeight: NSLayoutConstraint, bottom: NSLayoutConstraint, keyboardEdge: NSLayoutConstraint) {
        if let controller { addChild(controller) }
        barClip.translatesAutoresizingMaskIntoConstraints = false
        barClip.clipsToBounds = true
        view.addSubview(barClip)
        let keyboardEdge = addComposerFade(below: barClip)
        addKeyboardCornerCover(below: barClip)
        bar.translatesAutoresizingMaskIntoConstraints = false
        barClip.addSubview(bar)
        controller?.didMove(toParent: self)

        let clipHeightConstraint = barClip.heightAnchor.constraint(equalToConstant: 80)
        let bottomConstraint = barClip.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            barClip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barClip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
            clipHeightConstraint,
            bar.leadingAnchor.constraint(equalTo: barClip.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: barClip.trailingAnchor),
            // Bottom, not top: the bar grows upward out of the clip, so the composer row keeps its
            // place on the keyboard while the strip above it is uncovered.
            bar.bottomAnchor.constraint(equalTo: barClip.bottomAnchor),
            // As tall as the screen, whatever the bar's content measures, so the host never resizes.
            // Resized under a SwiftUI animation, it re-placed its bottom-aligned content outside that
            // animation while the content's own layout was still springing inside it, and the two
            // disagreed by the whole change in height: the composer lifted off the keyboard and slid
            // back. The clip alone decides how much of the bar is seen.
            bar.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])
        return (clipHeightConstraint, bottomConstraint, keyboardEdge)
    }

    /// Adds the fade from the bar's top edge down to the keyboard's top edge, or the screen's bottom
    /// with the keyboard down. Returns the bottom constraint, which `KeyboardFloor` drives.
    private func addComposerFade(below clip: UIView) -> NSLayoutConstraint {
        fade.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(fade, belowSubview: clip)
        fadeTopConstraint = fade.topAnchor.constraint(equalTo: clip.topAnchor)
        let bottom = fade.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fadeTopConstraint,
            bottom,
        ])
        return bottom
    }

    /// Fills the gap the keyboard's rounded corners open up behind the bar — see
    /// ``keyboardCornerCover``.
    private func addKeyboardCornerCover(below clip: UIView) {
        keyboardCornerCover.translatesAutoresizingMaskIntoConstraints = false
        keyboardCornerCover.backgroundColor = UIColor(Color.backgroundMain)
        keyboardCornerCover.isUserInteractionEnabled = false
        view.insertSubview(keyboardCornerCover, belowSubview: clip)
        NSLayoutConstraint.activate([
            keyboardCornerCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardCornerCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardCornerCover.topAnchor.constraint(equalTo: fade.bottomAnchor),
            keyboardCornerCover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Drops the composer's focus as the app leaves the foreground.
    ///
    /// UIKit otherwise restores the composer as first responder during the next activation and
    /// raises the keyboard with it. Anything that lowers the keyboard while that restore is still
    /// in flight — routing a deep link, say — leaves the keyboard with no owner, and SwiftUI keeps
    /// the inset it had already reserved for it, so a sheet presented by that routing is laid out
    /// around a keyboard that is no longer on screen. Resigning here happens while the app is
    /// still active and nothing is animating, which leaves the restore nothing to restore.
    private func lowerComposerOnResignActive() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.bar.firstTextInputResponder?.resignFirstResponder()
            }
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Bridge the transcript's scroll view to the navigation bar so the iOS 26 toolbar
        // scroll-edge effect engages as content scrolls under it. The bar reflects the SwiftUI
        // hosting controller (the navigation controller's direct child), not this nested
        // representable VC, so the content scroll view has to be set there — a hosted UIKit scroll
        // view isn't auto-detected the way a SwiftUI `ScrollView` is.
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController) {
            host = parent
        }
        host.setContentScrollView(transcript.collectionView, for: .top)
        // `topEdgeEffect` is the UIKit counterpart of the `softScrollEdge` modifier the SwiftUI
        // screens use — a UIKit scroll view the modifier cannot reach has to set it itself. Without
        // it the transcript is cut at a hard line where the bar's background ends; with it the
        // transcript blurs progressively as it passes under the bar, as the Chats list does.
        //
        // The bottom edge is the composer's, and it softens the same way, under the screen's own
        // dissolve — see `ComposerFadeView`. Both edge regions follow the scroll view's adjusted
        // inset, so this one tracks the keyboard without being told about it.
        if #available(iOS 26.0, *) {
            transcript.collectionView.topEdgeEffect.style = .soft
            transcript.collectionView.bottomEdgeEffect.style = .soft
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Raise the keyboard once, after the push transition settles — the composer's field is now
        // in the key window, so `becomeFirstResponder` presents the keyboard (a hosted SwiftUI
        // `@FocusState` set programmatically does not). One-shot: guarded so a later re-appear
        // (app foregrounding) doesn't force the keyboard back up.
        guard focusesComposerOnAppear, !didFocusComposer else { return }
        didFocusComposer = true
        focusComposer()
    }

    /// Raise the keyboard for the bar's field. A hosted SwiftUI `@FocusState` set programmatically
    /// moves the caret into the field but never makes it first responder across the hosting
    /// boundary, so the keyboard never arrives and the field takes no input — only this does. Waits
    /// out any open context menu, which owns the screen and would refuse the responder change.
    public func focusComposer() {
        transcript.afterContextMenu { [weak self] in
            self?.bar.firstTextInputResponder?.becomeFirstResponder()
        }
    }

    /// Keep the keyboard down, for a menu action that hands off to a sheet. The menu already lowered
    /// it, so the work here is cancelling the restore that would otherwise put the keyboard back on
    /// top of whatever the action presented; the resigns cover the callers that had no menu open.
    public func dismissKeyboard() {
        composerHeldKeyboardUnderMenu = false
        _ = bar.firstTextInputResponder?.resignFirstResponder()
        transcript.afterContextMenu { [weak self] in
            _ = self?.bar.firstTextInputResponder?.resignFirstResponder()
        }
    }

    /// The height between the top bar and the keyboard floor that the transcript would keep without
    /// the mention list, sent whenever it changes.
    public var onMentionRoomChange: ((CGFloat) -> Void)?

    /// How far the keyboard reaches up into the screen, in points; zero while it is down.
    public var keyboardOverlap: CGFloat {
        keyboardFloor?.overlap ?? 0
    }

    /// Whether the composer's field holds the keyboard and can take a replacement input view.
    public var canReplaceComposerInputView: Bool {
        guard let responder = bar.firstTextInputResponder, responder.isFirstResponder else { return false }
        return responder is UITextView || responder is UITextField
    }

    /// Shows `inputView` in the keyboard's place under the composer's field, or the system keyboard
    /// again for `nil`, without the field losing focus. Returns whether the field took it.
    @discardableResult
    public func setComposerInputView(_ inputView: UIView?) -> Bool {
        switch bar.firstTextInputResponder {
        case let textView as UITextView:
            guard textView.inputView !== inputView else { return true }
            textView.inputView = inputView
            textView.reloadInputViews()
            return true
        case let textField as UITextField:
            guard textField.inputView !== inputView else { return true }
            textField.inputView = inputView
            textField.reloadInputViews()
            return true
        default:
            return false
        }
    }

    /// Lays a clear layer over the transcript that takes every touch and fires `onTap` instead,
    /// while `isActive` holds; `nil` takes it down. Nothing under it sees the touch, so the keyboard
    /// stays up and no message reacts.
    public func setTranscriptShield(isActive: @escaping () -> Bool, onTap: (() -> Void)?) {
        transcriptShield?.removeFromSuperview()
        transcriptShield = nil
        guard let onTap else { return }
        let shield = TranscriptShield()
        shield.isActive = isActive
        shield.onTap = onTap
        shield.frame = transcript.view.frame
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(shield, aboveSubview: transcript.view)
        transcriptShield = shield
    }

    /// Set the bar's height to its measured SwiftUI content height. `accessories` says which cards
    /// stand above the composer row, which decides what the clip around the bar does with that height.
    ///
    /// Only the clip moves. The bar itself is as tall as the screen and pinned to the clip's bottom,
    /// so its content is already laid out at any height the clip uncovers.
    public func setBarHeight(_ height: CGFloat, accessories: BarAccessories) {
        // Read before the early exits: a card closing has to move the clip even though the measured
        // height does not change — the card stays mounted under the clip while it fades.
        let toggled = accessories.open != barAccessories.open
        // A change the bar draws itself, with a card open before and after it: the list changing its
        // row count, or one card splitting out of the other's glass or merging back into it. The glass
        // changes shape in SwiftUI, so the clip only has to stay out of its way.
        let inPlace = !accessories.open.isEmpty && !barAccessories.open.isEmpty
        barAccessories = accessories
        defer { reportMentionRoom() }
        measuredBarHeight = height
        guard barClipHeightConstraint != nil else { return }

        let isFirst = !didMeasureBar
        didMeasureBar = true
        let previousClip = barClipHeightConstraint.constant
        // A closing card is still in the measurement and has to come back off it. A card only
        // counts as open once it is measured, so the report that opens it already carries its height.
        let clipHeight = height - accessories.exitingHeight
        fade.isHidden = height <= 0
        guard clipHeight != previousClip else {
            // Back to the height a shrink is still holding the clip at, before the hold settled:
            // the settle no longer matches and won't run, so the transcript would keep reserving
            // the shrink's height and its last message would sit under the cards.
            if transcriptCover != nil, !isFirst {
                transcriptCover = nil
                fadeTopConstraint.constant = 0
                ChatMotion.replySurface.animate {
                    self.view.layoutIfNeeded()
                    self.updateTranscriptInset()
                }
            }
            return
        }

        if inPlace, !isFirst, view.window != nil {
            holdForInPlaceResize(clipHeight: clipHeight)
            return
        }
        if clipHeight < previousClip, !toggled, !isFirst, view.window != nil {
            holdForShrink(clipHeight: clipHeight)
            return
        }

        transcriptCover = nil
        fadeTopConstraint?.constant = 0
        barClipHeightConstraint.constant = clipHeight
        guard !isFirst, view.window != nil, toggled else {
            // Every other height — a draft wrapping to a second line, the send arrow appearing — is
            // one the content has *already* laid itself out at by the time the number arrives. The
            // clip matches it in the same frame; the transcript's inset comes with it, since
            // `viewDidLayoutSubviews` reads the clip's frame during this pass.
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
            }
            return
        }

        // A card opening or closing: the clip's edge travels, and that edge is the whole animation.
        // It uncovers the card on the way in and closes back over it on the way out. The transcript's
        // inset is read inside this pass too, so the bubbles are pushed by the edge rather than
        // teleporting ahead of it.
        ChatMotion.replySurface.animate {
            self.view.layoutIfNeeded()
        }
    }

    /// Shrinks the bar's room for a composer folding back to one row or dropping its chips.
    ///
    /// The transcript takes the new inset in this frame, unanimated, so a send's insertion moves its
    /// rows on its own spring alone. The clip stays at its old height until the glass's spring is
    /// done: cut at once, it would hide the text and caret still travelling down to their place.
    private func holdForShrink(clipHeight: CGFloat) {
        let heldClip = barClipHeightConstraint.constant
        transcriptCover = clipHeight
        fadeTopConstraint.constant = heldClip - clipHeight
        UIView.performWithoutAnimation {
            self.view.layoutIfNeeded()
            self.updateTranscriptInset()
        }
        let height = measuredBarHeight
        DispatchQueue.main.asyncAfter(deadline: .now() + ChatMotion.replySurface.duration) { [weak self] in
            // A later report may already have moved the bar on; only the one still current lands.
            guard let self, self.measuredBarHeight == height,
                  self.barClipHeightConstraint.constant == heldClip else { return }
            self.barClipHeightConstraint.constant = clipHeight
            self.transcriptCover = nil
            self.fadeTopConstraint.constant = 0
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
            }
        }
    }

    /// Makes room for a change the bar draws itself, without animating anything.
    ///
    /// The glass grows and shrinks on its own spring, its bottom on the composer, and a second
    /// animator here would only fight it. The clip takes the taller of the two heights at once, which
    /// can never cut into the glass, and comes down to a shrink's height once the spring is done.
    private func holdForInPlaceResize(clipHeight: CGFloat) {
        let heldClip = max(clipHeight, barClipHeightConstraint.constant)
        // The clip jumps, the transcript doesn't: it keeps reserving what it reserved until the
        // spring below moves it, so the bubbles ride the glass's edge instead of the clip's.
        let cover = transcriptCover ?? barClipHeightConstraint.constant
        transcriptCover = cover
        barClipHeightConstraint.constant = heldClip
        fadeTopConstraint.constant = heldClip - cover
        UIView.performWithoutAnimation {
            self.view.layoutIfNeeded()
        }
        transcriptCover = clipHeight
        fadeTopConstraint.constant = heldClip - clipHeight
        ChatMotion.replySurface.animate {
            self.view.layoutIfNeeded()
            self.updateTranscriptInset()
        }
        guard heldClip > clipHeight else {
            transcriptCover = nil
            return
        }
        let height = measuredBarHeight
        // Long enough for the slower of the two shape changes, the strip merging back into the list.
        let settle = max(ChatMotion.replySurface.duration, ChatMotion.replyMerge.duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            // A later report may already have moved the bar on; only the one still current lands.
            guard let self, self.measuredBarHeight == height,
                  self.barClipHeightConstraint.constant == heldClip else { return }
            self.barClipHeightConstraint.constant = clipHeight
            self.transcriptCover = nil
            self.fadeTopConstraint.constant = 0
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
            }
        }
    }

    public func update(items: [ChatItem]) { transcript.update(items: items) }
    public func scrollToBottom(animated: Bool = true) { transcript.scrollToBottom(animated: animated) }

    /// Whether the transcript sits at its newest message — see ``ChatViewController/isAtBottom``.
    public var isTranscriptAtBottom: Bool { transcript.isAtBottom }

    /// Brings a row into view, deferring until the update that contains it lands.
    public func scrollToMessage(id: String) { transcript.scrollToMessage(id: id) }

    // MARK: - Bar inset

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Before the pass, not after it: the safe area can change between passes — opening a chat
        // from the Chats tab starts it with the tab bar's inset and drops to the home indicator's a
        // pass later — and a bar moved after the pass leaves the transcript's inset below reading
        // the bar's old frame, with nothing to lay it out again.
        keyboardFloor.refresh()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.layoutHeld()
        refreshEditSpotlight()
        // Reserve what the bar covers beyond what the system already reserves. The system grows the
        // collection view's adjusted inset by the safe area, or by the keyboard when it's up, so
        // counting those again overscrolls by a whole keyboard. Measured from the bar's top edge
        // rather than taken as its height, so a bar resting into the safe area gives that back.
        updateTranscriptInset()
        reportMentionRoom()
    }

    private func updateTranscriptInset() {
        let top = barClip.frame.maxY - (transcriptCover ?? barClip.frame.height)
        let covered = view.bounds.maxY - top
        let drop = keyboardFloor.isKeyboardUp ? Self.raisedTranscriptDrop : 0
        transcript.setBottomInset(max(0, covered - keyboardFloor.systemInset - drop))
    }

    /// Sends the transcript's room without the mention list: from the top bar's bottom edge down to
    /// the keyboard floor, less the rest of the bar. Measured, so a reply strip that wraps counts.
    ///
    /// Also sent from ``setBarHeight(_:accessories:)``: a bar height that changes inside the clip
    /// only lays out the clip, so the root view's layout pass never comes.
    private func reportMentionRoom() {
        guard let onMentionRoomChange, didMeasureBar else { return }
        let top: CGFloat
        if let navigationBar = hostNavigationController?.navigationBar, !navigationBar.isHidden {
            top = max(view.safeAreaInsets.top, navigationBar.convert(navigationBar.bounds, to: view).maxY)
        } else {
            top = view.safeAreaInsets.top
        }
        let room = barClip.frame.maxY - top - barAccessories.restHeight
        guard room != reportedMentionRoom else { return }
        reportedMentionRoom = room
        onMentionRoomChange(room)
    }
}

/// Holds a bar clear of the keyboard by driving its bottom constraint from the keyboard
/// notifications.
///
/// `UIView.keyboardLayoutGuide` is the shorter way to write this and is what this screen used
/// to do, but the guide is per-view and can be torn down for good: presenting the tipcard's
/// sheet over an open chat collapses that chat view's guide to a zero-size frame at the bottom
/// of the screen, and it never tracks again — no layout pass, safe-area toggle, or later
/// presentation brings it back, so the composer sits behind the keyboard for as long as the
/// screen is up. The notifications keep reporting the right frame the whole time.
@MainActor
private final class KeyboardFloor {

    private let bottomConstraint: NSLayoutConstraint
    /// Tracks the keyboard's top edge itself: the screen's bottom with the keyboard down.
    private let keyboardEdgeConstraint: NSLayoutConstraint
    private weak var view: UIView?
    private var observer: (any NSObjectProtocol)?

    /// The keyboard's current overlap of the view, in points; zero when it is down.
    private(set) var overlap: CGFloat = 0

    init(view: UIView, bottomConstraint: NSLayoutConstraint, keyboardEdgeConstraint: NSLayoutConstraint) {
        self.view = view
        self.bottomConstraint = bottomConstraint
        self.keyboardEdgeConstraint = keyboardEdgeConstraint

        // `willChangeFrame` alone covers showing, hiding, height changes and the interactive
        // drag-to-dismiss, all of which post it.
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let info = notification.userInfo
            let endFrame = info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            let curve = info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            let isLocal = info?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true
            MainActor.assumeIsolated {
                // Another process's keyboard — the Messages composer a share sheet hosts over this
                // screen, say — is not one the bar has to clear, and its lowering can arrive with
                // no usable frame, which would strand the bar at its height with nothing under it.
                guard isLocal else { return }
                // A zero end frame says nothing about where the keyboard is; UIKit posts one as
                // the app returns to the foreground. Taken literally its top edge is the top of
                // the screen, which would drive the bar up over the transcript.
                guard let endFrame, !endFrame.isEmpty else { return }
                self?.apply(endFrame: endFrame, duration: duration ?? 0, curve: curve)
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Re-applies the current overlap. Called from layout so the resting inset picks up a safe
    /// area that wasn't known yet when the bar was added. Returns whether the bar moved.
    @discardableResult
    func refresh() -> Bool {
        setInset(max(overlap, restingInset))
    }

    private func apply(endFrame: CGRect, duration: TimeInterval, curve: UInt?) {
        guard let view, view.window != nil else { return }

        // Keyboard frames arrive in window coordinates.
        let frameInView = view.convert(endFrame, from: nil)
        overlap = max(0, view.bounds.maxY - frameInView.minY)
        let edgeMoved = keyboardEdgeConstraint.constant != -overlap
        keyboardEdgeConstraint.constant = -overlap
        guard setInset(max(overlap, restingInset)) || edgeMoved else { return }

        let options: UIView.AnimationOptions = [
            .beginFromCurrentState,
            curve.map { UIView.AnimationOptions(rawValue: $0 << 16) } ?? .curveEaseInOut,
        ]
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            view.layoutIfNeeded()
        }
    }

    /// How far into the bottom safe area the bar rests with the keyboard down.
    var restingDrop: CGFloat = 0

    /// What the system itself reserves at the bottom of a scroll view in this view: the keyboard
    /// while it is up, the safe area otherwise.
    var systemInset: CGFloat {
        max(overlap, safeAreaBottom)
    }

    /// Whether the keyboard reaches above the safe area, and so holds the bar up.
    var isKeyboardUp: Bool {
        overlap > safeAreaBottom
    }

    private var safeAreaBottom: CGFloat {
        view?.safeAreaInsets.bottom ?? 0
    }

    /// The keyboard-down resting inset: the safe area less the drop, never below the screen's edge.
    /// The host runs this screen under the home indicator, so the safe area is the window's.
    private var restingInset: CGFloat {
        max(0, safeAreaBottom - restingDrop)
    }

    /// Returns whether the constraint actually moved, so callers can skip a no-op animation.
    @discardableResult
    private func setInset(_ inset: CGFloat) -> Bool {
        guard bottomConstraint.constant != -inset else { return false }
        bottomConstraint.constant = -inset
        return true
    }
}

private extension UIView {
    /// The first descendant text-input view that can become first responder — the composer's
    /// field, wherever SwiftUI nests it inside the hosted bar.
    var firstTextInputResponder: UIView? {
        if (self is UITextField || self is UITextView), canBecomeFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.firstTextInputResponder { return responder }
        }
        return nil
    }
}

#endif

/// The box the bar is seen through, which also lets touches reach the bar where it reaches above the
/// box — see ``ChatScreenViewController/barOverflowsTop``.
private final class BarClipView: UIView {

    /// The subview allowed to take touches outside the box's bounds, while the bar overflows.
    weak var overflowTarget: UIView?
    /// Where, in window coordinates, the target starts taking those touches; `nil` for all of it.
    var overflowTouchTop: CGFloat?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let overflowTarget {
            var region = overflowTarget.frame
            if let overflowTouchTop {
                let top = max(region.minY, convert(CGPoint(x: 0, y: overflowTouchTop), from: nil).y)
                region = CGRect(x: region.minX, y: top, width: region.width, height: max(0, region.maxY - top))
            }
            if region.contains(point) { return true }
        }
        return super.point(inside: point, with: event)
    }
}

/// A clear layer that swallows touches while its predicate holds and passes them through otherwise.
private final class TranscriptShield: UIView {

    var isActive: () -> Bool = { false }
    var onTap: () -> Void = {}

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        isActive() && bounds.contains(point) ? self : nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTap()
    }
}
