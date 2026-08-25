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
    /// The bar's height is driven by its *measured* SwiftUI height, so the frame matches its
    /// content exactly — a hosting controller's intrinsic size mis-measures multiline growth and
    /// lets the composer overflow below its frame, under the keyboard.
    private var barHeightConstraint: NSLayoutConstraint!
    /// Keeps the bar above the keyboard. Not `view.keyboardLayoutGuide`: see `KeyboardFloor`.
    private var keyboardFloor: KeyboardFloor!

    /// Raise the keyboard once the screen has finished appearing (post-tip open). Driven from
    /// UIKit rather than a SwiftUI `@FocusState`: a hosted composer's programmatic focus updates
    /// SwiftUI's focus state but never presents the keyboard across the hosting boundary — only a
    /// real `becomeFirstResponder` does.
    public var focusesComposerOnAppear = false
    private var didFocusComposer = false

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
        barHeightConstraint = constraints.height
        keyboardFloor = KeyboardFloor(view: view, bottomConstraint: constraints.bottom)
        lowerComposerOnResignActive()
    }

    /// Adds a hosted bar pinned to the view's width and bottom; returns the height constraint
    /// (driven later by the bar's measured SwiftUI content height) and the bottom constraint
    /// (driven by the keyboard).
    private func addBar(
        _ bar: UIView,
        controller: UIViewController?
    ) -> (height: NSLayoutConstraint, bottom: NSLayoutConstraint) {
        if let controller { addChild(controller) }
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        controller?.didMove(toParent: self)

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 80)
        let bottomConstraint = bar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
            heightConstraint,
        ])
        return (heightConstraint, bottomConstraint)
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
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Raise the keyboard once, after the push transition settles — the composer's field is now
        // in the key window, so `becomeFirstResponder` presents the keyboard (a hosted SwiftUI
        // `@FocusState` set programmatically does not). One-shot: guarded so a later re-appear
        // (app foregrounding) doesn't force the keyboard back up.
        guard focusesComposerOnAppear, !didFocusComposer else { return }
        didFocusComposer = true
        bar.firstTextInputResponder?.becomeFirstResponder()
    }

    /// Set the bar's height to its measured SwiftUI content height.
    public func setBarHeight(_ height: CGFloat) {
        guard barHeightConstraint != nil, barHeightConstraint.constant != height else { return }
        barHeightConstraint.constant = height
    }

    // MARK: - Data passthrough

    public func update(items: [ChatItem]) { transcript.update(items: items) }
    public func scrollToBottom(animated: Bool = true) { transcript.scrollToBottom(animated: animated) }

    // MARK: - Bar inset

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardFloor.refresh()
        // Reserve only the bar's own height. On-device the system already grows the collection
        // view's adjusted content inset by the keyboard when it's up, so adding the keyboard here
        // too (via the bar's risen position) double-counts it and overscrolls by a whole keyboard.
        transcript.setBottomInset(bar.frame.height)
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
#endif
