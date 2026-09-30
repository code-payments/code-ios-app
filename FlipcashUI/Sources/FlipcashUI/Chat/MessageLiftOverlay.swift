//
//  MessageLiftOverlay.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// A lifted bubble with its reaction strip above it and its action menu below it, in a window over
/// the keyboard. `MessageLiftLayout` places all three; this owns the views and their motion. The
/// screen behind stays the caller's: it blurs the transcript and hands the copy over.
@MainActor
final class MessageLiftOverlay: NSObject, UIGestureRecognizerDelegate {

    /// Fired when a strip emoji is tapped.
    var onStripSelect: ((String) -> Void)?
    /// Fired when the strip's "+" is tapped.
    var onStripAdd: (() -> Void)?
    /// Fired when a menu row is chosen, before its action is performed.
    var onAction: ((UIAction) -> Void)?
    /// Fired by a tap outside the strip and menu, or the accessibility escape gesture.
    var onDismissRequest: (() -> Void)?

    private var window: UIWindow?
    private var copy: UIView?
    private var strip: ReactionStripView?
    private var menu: MessageMenuView?
    /// The side the lift hugs, so the strip and menu grow out of and collapse into its corner.
    private var hugsTrailing = false
    /// Where the copy was lifted from, which it returns to when its row has left the screen.
    private var home: CGRect = .null
    /// Holds off the menu until the pressing finger drags away; `nil` when no finger is down.
    private var drag: LiftDragGate?

    /// Whether a lift is on screen.
    var isPresented: Bool { window != nil }

    /// Lifts `copy` from `home` (window coordinates), with a strip of `entries` above it and a menu
    /// of `actions` below it; either may be absent. `press` is where a finger still down from a long
    /// press landed (window coordinates), which may go on to drag onto a menu row.
    func present(copy: UIView, from home: CGRect, in scene: UIWindowScene, entries: [ReactionStrip.Entry]?, actions: [UIAction]?, press: CGPoint? = nil) {
        let window = UIWindow(windowScene: scene)
        // Above the keyboard's window, so the lift covers it as it goes down.
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIViewController()
        let root = LiftRootView()
        root.onEscape = { [weak self] in self?.onDismissRequest?() }
        root.accessibilityViewIsModal = true
        host.view = root
        window.rootViewController = host
        window.isHidden = false
        let tapOutside = UITapGestureRecognizer(target: self, action: #selector(tappedOutside))
        tapOutside.delegate = self
        root.addGestureRecognizer(tapOutside)
        self.window = window
        self.home = home
        drag = press.map(LiftDragGate.init(origin:))
        hugsTrailing = home.midX > root.bounds.midX

        copy.bounds = CGRect(origin: .zero, size: home.size)
        copy.center = CGPoint(x: home.midX, y: home.midY)
        root.addSubview(copy)
        self.copy = copy

        let menuActions = actions.flatMap { $0.isEmpty ? nil : $0 }
        let layout = MessageLiftLayout(
            bubble: home,
            bounds: root.bounds,
            safeArea: (window.safeAreaInsets.top, window.safeAreaInsets.bottom),
            stripHeight: entries == nil ? nil : ReactionStripView.height,
            stripGap: ReactionStripView.bubbleGap,
            menuSize: menuActions.map { MessageMenuView.size(rows: $0.count) }
        )

        let scale = layout.bubble.height / home.height
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            copy.center = CGPoint(x: layout.bubble.midX, y: layout.bubble.midY)
            copy.transform = CGAffineTransform(scaleX: scale, y: scale)
        }

        if let entries, let stripTop = layout.stripTop {
            strip = installStrip(entries: entries, in: root, besides: layout.bubble, top: stripTop)
        }
        if let menuActions, let frame = layout.menu {
            let menu = MessageMenuView(actions: menuActions)
            menu.frame = frame
            menu.onSelect = { [weak self] action in self?.onAction?(action) }
            root.addSubview(menu)
            self.menu = menu
            reveal(menu, fromTop: true)
        }
    }

    /// Follows a pressing finger at `point` (window coordinates) over the menu.
    func track(_ point: CGPoint) {
        guard let menu, let window, drag?.admits(point) == true else { return }
        menu.track(menu.convert(point, from: window))
    }

    /// Chooses the menu row under a finger lifting at `point` (window coordinates), if it dragged
    /// there.
    func release(at point: CGPoint) {
        defer { drag = nil }
        guard let menu, let window, drag?.admits(point) == true else { return }
        menu.release(at: menu.convert(point, from: window))
    }

    /// When, into a landing with no row to land on, the copy starts fading out, and how long that takes.
    static let handoffDelay = ChatMotion.contextMenuLanding * 0.75
    static let handoffDuration = ChatMotion.contextMenuLanding * 0.25

    /// How long the strip and menu take to fade out once a dismissal starts.
    static let accessoryFadeDuration = ChatMotion.contextMenuLanding * 0.4

    /// Flies the copy back while the strip and menu collapse into it, then takes the window down and
    /// calls `completion`. With a `landing`, the copy moves into `landing.container` and flies to
    /// `landing.frame` (container coordinates) as part of it, so the navigation bar and composer
    /// draw over it exactly as they do over the row it hands off to; returns the moved copy. Without
    /// one it flies to where it was lifted from and fades out, and returns `nil`.
    @discardableResult
    func dismiss(landingIn landing: (container: UIView, frame: CGRect)?, completion: @escaping () -> Void) -> UIView? {
        guard let window else {
            completion()
            return nil
        }
        self.window = nil
        let copy = copy, strip = strip, menu = menu
        self.copy = nil
        self.strip = nil
        self.menu = nil

        var target = CGPoint(x: home.midX, y: home.midY)
        var movedCopy: UIView?
        if let copy, let landing, let root = copy.superview {
            let center = landing.container.convert(copy.center, from: root)
            // Just above the cells and below whatever the container draws over them, such as the
            // scroll edge effect under the navigation bar, which has to soften the copy as it does
            // the row.
            if let topCell = landing.container.subviews.last(where: { $0 is UICollectionReusableView }) {
                landing.container.insertSubview(copy, aboveSubview: topCell)
            } else {
                landing.container.addSubview(copy)
            }
            copy.center = center
            target = CGPoint(x: landing.frame.midX, y: landing.frame.midY)
            movedCopy = copy
        }

        if let copy {
            BubbleBackgroundView.fadeLift(copy, duration: ChatMotion.contextMenuLanding)
        }
        let collapsedStrip = strip.map { Self.collapsedTransform($0.bounds.size, towardTrailing: hugsTrailing, towardTop: false) }
        let collapsedMenu = menu.map { Self.collapsedTransform($0.bounds.size, towardTrailing: hugsTrailing, towardTop: true) }
        UIView.animate(withDuration: ChatMotion.contextMenuLanding, delay: 0, options: .curveEaseInOut) {
            copy?.transform = .identity
            copy?.center = target
            if let strip, let collapsedStrip {
                strip.transform = collapsedStrip
            }
            if let menu, let collapsedMenu {
                menu.transform = collapsedMenu
            }
        } completion: { _ in
            movedCopy?.removeFromSuperview()
            window.isHidden = true
            completion()
        }
        // The strip and menu are gone before the backdrop has cleared the title bar and composer,
        // so they never draw over either while collapsing.
        UIView.animate(withDuration: Self.accessoryFadeDuration, delay: 0, options: .curveEaseOut) {
            strip?.alpha = 0
            menu?.alpha = 0
        }
        if movedCopy == nil {
            UIView.animate(withDuration: Self.handoffDuration, delay: Self.handoffDelay, options: .curveLinear) {
                copy?.alpha = 0
            }
        }
        return movedCopy
    }

    @objc private func tappedOutside() {
        onDismissRequest?()
    }

    /// Leaves touches on the strip and menu to their own controls: a menu row is a plain
    /// `UIControl`, which an ancestor's tap recognizer would otherwise beat to the tap.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !(menu.map(view.isDescendant(of:)) ?? false) && !(strip.map(view.isDescendant(of:)) ?? false)
    }

    /// Adds the strip at `top`, pinned to the side of `bubble` the bubble hugs, and grows it in.
    private func installStrip(entries: [ReactionStrip.Entry], in root: UIView, besides bubble: CGRect, top: CGFloat) -> ReactionStripView {
        let strip = ReactionStripView()
        strip.configure(entries: entries)
        strip.alpha = 0
        strip.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(strip)
        let margin = MessageLiftLayout.sideMargin
        let bounds = root.bounds
        let hug = hugsTrailing
            ? strip.trailingAnchor.constraint(equalTo: root.leadingAnchor, constant: min(bubble.maxX, bounds.width - margin))
            : strip.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: max(bubble.minX, margin))
        hug.priority = .defaultHigh
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: margin),
            strip.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -margin),
            strip.topAnchor.constraint(equalTo: root.topAnchor, constant: top),
            hug,
        ])
        strip.onSelect = { [weak self] emoji in self?.onStripSelect?(emoji) }
        strip.onAdd = { [weak self] in self?.onStripAdd?() }
        root.layoutIfNeeded()
        strip.revealEntries(fromTrailing: hugsTrailing)
        reveal(strip, fromTop: false)
        return strip
    }

    /// Grows `view` out of the bubble's corner: from its top edge for a view below the bubble, from
    /// its bottom edge for one above.
    private func reveal(_ view: UIView, fromTop: Bool) {
        view.alpha = 0
        view.transform = Self.collapsedTransform(view.bounds.size, towardTrailing: hugsTrailing, towardTop: fromTop)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0) {
            view.transform = .identity
            view.alpha = 1
        }
    }

    /// A view of `size` shrunk into the corner nearest the bubble.
    private static func collapsedTransform(_ size: CGSize, towardTrailing: Bool, towardTop: Bool) -> CGAffineTransform {
        let scale: CGFloat = 0.3
        let dx = size.width * (1 - scale) / 2 * (towardTrailing ? 1 : -1)
        let dy = size.height * (1 - scale) / 2 * (towardTop ? -1 : 1)
        return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
    }
}

/// Whether a finger still down from the long press may track the menu. The menu can open under a
/// finger that hasn't moved, so a row answers only once the finger has dragged away from the press.
nonisolated struct LiftDragGate {
    /// How far the finger travels from the press before it tracks the menu.
    static let threshold: CGFloat = 10
    /// Where the press landed.
    let origin: CGPoint
    private var isOpen = false

    init(origin: CGPoint) {
        self.origin = origin
    }

    /// Whether the finger at `point` may track the menu; it stays admitted once it has been.
    mutating func admits(_ point: CGPoint) -> Bool {
        if !isOpen {
            isOpen = hypot(point.x - origin.x, point.y - origin.y) > Self.threshold
        }
        return isOpen
    }
}

/// The overlay's root, which routes VoiceOver's escape gesture to a dismissal.
private final class LiftRootView: UIView {
    var onEscape: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityPerformEscape() -> Bool {
        onEscape?()
        return true
    }
}
#endif
