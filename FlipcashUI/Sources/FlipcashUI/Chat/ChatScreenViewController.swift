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
    private let barClip = UIView()
    /// The bar's height is driven by its *measured* SwiftUI height, so the frame matches its
    /// content exactly — a hosting controller's intrinsic size mis-measures multiline growth and
    /// lets the composer overflow below its frame, under the keyboard. Always applied unanimated.
    private var barHeightConstraint: NSLayoutConstraint!
    /// The clip's height — what the screen and the transcript actually see as the bar. Equal to the
    /// bar's own height except while the reply strip is arriving or leaving.
    private var barClipHeightConstraint: NSLayoutConstraint!
    /// Keeps the bar above the keyboard. Not `view.keyboardLayoutGuide`: see `KeyboardFloor`.
    private var keyboardFloor: KeyboardFloor!
    /// Fades the transcript into the navigation bar. See `TranscriptTopFade`.
    private let topFade = TranscriptTopFade()
    private var topFadeHeightConstraint: NSLayoutConstraint!
    /// How far below the navigation bar the fade finishes.
    private static let topFadeTail: CGFloat = 36

    /// Raise the keyboard once the screen has finished appearing (post-tip open). Driven from
    /// UIKit rather than a SwiftUI `@FocusState`: a hosted composer's programmatic focus updates
    /// SwiftUI's focus state but never presents the keyboard across the hosting boundary — only a
    /// real `becomeFirstResponder` does.
    public var focusesComposerOnAppear = false
    private var didFocusComposer = false
    /// Whether the composer held the keyboard when the current context menu opened, and so should get
    /// it back when that menu goes. Cleared by `dismissKeyboard()` so an action handing off to a sheet
    /// isn't fought by the restore.
    private var composerHeldKeyboardUnderMenu = false
    /// The blur shown behind a context menu, and held past it for an edit.
    private let backdrop = MessageBackdrop()
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

    /// Whether the last measured bar height included the reply strip.
    private var barShowsReply = false
    /// What the strip added to the bar when it opened, so the clip knows what to close back over.
    /// The bar itself still reports the taller height on the way out — the strip stays mounted under
    /// the clip while it fades — so the closed height cannot be read off the measurement.
    private var replyStripHeight: CGFloat = 0
    /// The pop gestures switched off for the length of an edit, kept so only those are switched back
    /// on and one that was already off stays off.
    private var suspendedPopGestures: [UIGestureRecognizer] = []

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

    public var onContactAction: (() -> Void)? {
        get { transcript.onContactAction }
        set { transcript.onContactAction = newValue }
    }

    /// Forwards profile-card taps from the transcript to the owner.
    public var onProfileTap: (() -> Void)? {
        get { transcript.onProfileTap }
        set { transcript.onProfileTap = newValue }
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

        topFade.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topFade)
        topFadeHeightConstraint = topFade.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            topFade.topAnchor.constraint(equalTo: view.topAnchor),
            topFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topFadeHeightConstraint,
        ])

        let constraints = addBar(bar, controller: barController)
        barHeightConstraint = constraints.height
        barClipHeightConstraint = constraints.clipHeight
        keyboardFloor = KeyboardFloor(view: view, bottomConstraint: constraints.bottom)
        lowerComposerOnResignActive()
        handOffComposerFocusAroundContextMenu()
        backdrop.onTap = { [weak self] in self?.onCancelEdit?() }
        transcript.onScroll = { [weak self] in self?.refreshEditSpotlight() }
    }

    /// Blurs the screen behind a context menu, takes the keyboard down for its lifetime, and puts
    /// both back once the menu has gone.
    ///
    /// UIKit hides the keyboard for a context menu's whole lifetime but leaves the field first
    /// responder, so the composer is left with a blinking caret, no keyboard, and no way to type
    /// into it. Resigning as the menu comes on screen makes that an ordinary dismissal — the keyboard
    /// animates away alongside the menu rather than at the long-press threshold, and the composer
    /// looks as unfocused as it now is — and re-taking the responder as the menu starts to go
    /// restores what the long press interrupted, whether the menu closed on an action or on a tap
    /// outside.
    private func handOffComposerFocusAroundContextMenu() {
        transcript.onContextMenuWillPresent = { [weak self] animator in
            guard let self else { return }
            backdrop.present(over: contextMenuBackdropHost, animator: animator)
            guard let responder = bar.firstTextInputResponder else { return }
            composerHeldKeyboardUnderMenu = responder.isFirstResponder
            _ = responder.resignFirstResponder()
        }
        transcript.onContextMenuDidDismiss = { [weak self] animator in
            guard let self else { return }
            backdrop.dismiss(animator: animator)
            guard composerHeldKeyboardUnderMenu else { return }
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
        backdrop.present(over: contextMenuBackdropHost, animator: nil)
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
    /// returns the bar's own height constraint and the clip's (both driven later by the bar's
    /// measured SwiftUI content height) and the clip's bottom constraint (driven by the keyboard).
    private func addBar(
        _ bar: UIView,
        controller: UIViewController?
    ) -> (height: NSLayoutConstraint, clipHeight: NSLayoutConstraint, bottom: NSLayoutConstraint) {
        if let controller { addChild(controller) }
        barClip.translatesAutoresizingMaskIntoConstraints = false
        barClip.clipsToBounds = true
        view.addSubview(barClip)
        bar.translatesAutoresizingMaskIntoConstraints = false
        barClip.addSubview(bar)
        controller?.didMove(toParent: self)

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 80)
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
            heightConstraint,
        ])
        return (heightConstraint, clipHeightConstraint, bottomConstraint)
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
        // screens use. Without it the transcript is cut at a hard line where the bar's background
        // ends; with it that background is gone, which is what `TranscriptTopFade` replaces.
        if #available(iOS 26.0, *) {
            transcript.collectionView.topEdgeEffect.style = .soft
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

    /// Set the bar's height to its measured SwiftUI content height. `replying` says whether a reply
    /// is open, which decides what the clip around the bar does with that height.
    ///
    /// The bar always takes the height flat. It is pinned to the bottom of the clip, so its own
    /// frame can change by the strip's whole height without moving anything that is on screen.
    public func setBarHeight(_ height: CGFloat, replying: Bool) {
        // Read before the early exits: a reply closing has to move the clip even though the measured
        // height does not change — the strip stays mounted under the clip while it fades.
        let opensReply = replying && !barShowsReply
        let closesReply = !replying && barShowsReply
        barShowsReply = replying
        guard barHeightConstraint != nil else { return }

        // A reply's own height is not known when it opens. On a first reply the strip mounts at zero
        // height, reports what it wants, and takes it a pass later; re-replying while the last one is
        // still fading keeps the strip it already has and never reports again. So the opening is
        // whichever pass actually makes the bar taller after the target changed, not the target
        // change itself — and once that height is known, later ones are ordinary bar growth.
        if opensReply { replyStripHeight = 0 }
        let previousClip = barClipHeightConstraint.constant
        let clipHeight: CGFloat
        let travels: Bool
        if replying {
            clipHeight = height
            travels = replyStripHeight == 0 && clipHeight != previousClip
            if travels { replyStripHeight = clipHeight - previousClip }
        } else {
            // Closing, the strip is still in the measurement and has to come back off it.
            clipHeight = closesReply ? height - replyStripHeight : height
            travels = closesReply
            if !closesReply { replyStripHeight = 0 }
        }

        let isFirst = !didMeasureBar
        didMeasureBar = true
        guard !isFirst, view.window != nil, travels else {
            guard barHeightConstraint.constant != height || barClipHeightConstraint.constant != clipHeight else { return }
            barHeightConstraint.constant = height
            barClipHeightConstraint.constant = clipHeight
            // Every other height — a draft wrapping to a second line, the send arrow appearing — is
            // one the content has *already* laid itself out at by the time the number arrives. Clip
            // and bar match it in the same frame; the transcript's inset comes with them, since
            // `viewDidLayoutSubviews` reads the clip's frame during this pass.
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
            }
            return
        }

        // Two passes, deliberately. The bar takes its new height first, with the clip still at the
        // old one, so the strip is laid out at full size behind the clip's edge and the composer row
        // is already standing where it will stay.
        barHeightConstraint.constant = height
        UIView.performWithoutAnimation {
            self.view.layoutIfNeeded()
        }
        // Then the clip's edge travels, and that edge is the whole animation: it uncovers the strip
        // on the way in and closes back over it on the way out. The transcript's inset is read inside
        // this pass too, so the bubbles are pushed by the edge rather than teleporting ahead of it.
        barClipHeightConstraint.constant = clipHeight
        ChatMotion.replySurface.animate {
            self.view.layoutIfNeeded()
        }
    }

    public func update(items: [ChatItem]) { transcript.update(items: items) }
    public func scrollToBottom(animated: Bool = true) { transcript.scrollToBottom(animated: animated) }

    /// Brings a row into view, deferring until the update that contains it lands.
    public func scrollToMessage(id: String) { transcript.scrollToMessage(id: id) }

    // MARK: - Bar inset

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardFloor.refresh()
        // The bar underlaps the transcript, so the safe-area inset measures the height the fade
        // has to stay opaque for; it holds until just above the title and clears over the tail.
        topFadeHeightConstraint.constant = view.safeAreaInsets.top + Self.topFadeTail
        topFade.opaqueLength = max(view.safeAreaInsets.top - 12, 0)
        backdrop.layoutHeld()
        refreshEditSpotlight()
        // Reserve only the bar's own height. On-device the system already grows the collection
        // view's adjusted content inset by the keyboard when it's up, so adding the keyboard here
        // too (via the bar's risen position) double-counts it and overscrolls by a whole keyboard.
        transcript.setBottomInset(barClip.frame.height)
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
    private weak var view: UIView?
    private var observer: (any NSObjectProtocol)?

    /// The keyboard's current overlap of the view, in points; zero when it is down.
    private var overlap: CGFloat = 0

    init(view: UIView, bottomConstraint: NSLayoutConstraint) {
        self.view = view
        self.bottomConstraint = bottomConstraint

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
            MainActor.assumeIsolated {
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
    /// area that wasn't known yet when the bar was added.
    func refresh() {
        setInset(max(overlap, restingInset))
    }

    private func apply(endFrame: CGRect, duration: TimeInterval, curve: UInt?) {
        guard let view, view.window != nil else { return }

        // Keyboard frames arrive in window coordinates.
        let frameInView = view.convert(endFrame, from: nil)
        overlap = max(0, view.bounds.maxY - frameInView.minY)
        guard setInset(max(overlap, restingInset)) else { return }

        let options: UIView.AnimationOptions = [
            .beginFromCurrentState,
            curve.map { UIView.AnimationOptions(rawValue: $0 << 16) } ?? .curveEaseInOut,
        ]
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            view.layoutIfNeeded()
        }
    }

    /// The keyboard-down resting inset. Zero wherever the host already ends the view at the safe
    /// area, which is what the SwiftUI container hosting this screen does — taking the window's
    /// inset instead counts the home indicator twice and parks the bar over the transcript.
    private var restingInset: CGFloat {
        view?.safeAreaInsets.bottom ?? 0
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

/// The transcript's fade into the navigation bar: opaque background colour for `opaqueLength`,
/// then a gradient to clear over the rest of its height.
///
/// The soft `topEdgeEffect` blurs what scrolls under the bar but does not darken it, and a cash
/// card's amount is large white text — blurred, it still reads over the title and up into the
/// status bar. This takes that content to the background colour instead, the way `WalletScreen`
/// fades its own bar-less top.
private final class TranscriptTopFade: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    /// Height, from the top, that stays fully opaque before the gradient starts.
    var opaqueLength: CGFloat = 0 {
        didSet {
            guard opaqueLength != oldValue else { return }
            setNeedsLayout()
        }
    }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resolved here rather than once at init so a trait change repaints the gradient.
        let background = UIColor(Color.backgroundMain).resolvedColor(with: traitCollection)
        gradient.colors = [background.cgColor, background.cgColor, background.withAlphaComponent(0).cgColor]
        let hold = bounds.height > 0 ? min(opaqueLength / bounds.height, 1) : 0
        gradient.locations = [0, NSNumber(value: Double(hold)), 1]
    }
}

#endif
