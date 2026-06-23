//
//  ChatScreenViewController.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// The full chat screen, entirely in UIKit: the transcript fills the view and two injected bars
/// float over its bottom (so content flows under them). The owner supplies both — a resting Send Cash
/// / Send Message bar pinned to the safe area, and a composer pinned to the keyboard guide — so this
/// screen stays agnostic about *what* the bars are and only owns layout + keyboard handling.
///
/// Keyboard handling is deliberately *not* hand-rolled. The host's safe area already grows to
/// include the keyboard, so the keyboard bar is pinned to the keyboard layout guide (it rides the
/// keyboard for free) and the transcript only reserves the active bar's own height — the safe area
/// supplies the keyboard. Doing both ourselves was what double-counted the keyboard. The resting bar
/// pins to the safe area so it never rides the keyboard.
public final class ChatScreenViewController: UIViewController {

    private let transcript = ChatViewController()
    private let restingBar: UIView
    private let keyboardBar: UIView
    private let restingBarController: UIViewController?
    private let keyboardBarController: UIViewController?
    /// Each bar's height is driven by its *measured* SwiftUI height, so the frame matches its content
    /// exactly — a hosting controller's intrinsic size mis-measures multiline growth and lets the
    /// composer overflow below its frame, under the keyboard.
    private var restingBarHeightConstraint: NSLayoutConstraint!
    private var keyboardBarHeightConstraint: NSLayoutConstraint!
    /// Which bar the transcript reserves bottom inset for; the composer can grow tall.
    private var isComposing = false

    /// - Parameters:
    ///   - restingBar: pinned over the transcript's bottom safe area; does not ride the keyboard.
    ///   - keyboardBar: pinned to the keyboard layout guide; rides the keyboard.
    ///   - restingBarController/keyboardBarController: the view controllers owning each bar, when
    ///     hosted (e.g. a `UIHostingController` for a SwiftUI bar). Adopted as children so their
    ///     lifecycle and environment work. Pass `nil` for a plain `UIView` bar.
    public init(
        restingBar: UIView,
        keyboardBar: UIView,
        restingBarController: UIViewController? = nil,
        keyboardBarController: UIViewController? = nil
    ) {
        self.restingBar = restingBar
        self.keyboardBar = keyboardBar
        self.restingBarController = restingBarController
        self.keyboardBarController = keyboardBarController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var onReachTop: (() -> Void)? {
        get { transcript.onReachTop }
        set { transcript.onReachTop = newValue }
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

        // Resting bar first, then the keyboard bar on top — when the keyboard is down they overlap at
        // the bottom and the keyboard bar (non-interactive then) must not occlude the buttons.
        restingBarHeightConstraint = addBar(restingBar, controller: restingBarController, pinnedTo: view.safeAreaLayoutGuide.bottomAnchor)
        keyboardBarHeightConstraint = addBar(keyboardBar, controller: keyboardBarController, pinnedTo: view.keyboardLayoutGuide.topAnchor)

        applyBarInteraction()
    }

    /// Adds a hosted bar pinned to the view's width and the given bottom anchor; returns its height
    /// constraint (driven later by the bar's measured SwiftUI content height).
    private func addBar(_ bar: UIView, controller: UIViewController?, pinnedTo bottomAnchor: NSLayoutYAxisAnchor) -> NSLayoutConstraint {
        if let controller { addChild(controller) }
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        controller?.didMove(toParent: self)

        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 80)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,
        ])
        return heightConstraint
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

    /// Set the resting bar's height to its measured SwiftUI content height.
    public func setRestingBarHeight(_ height: CGFloat) {
        guard restingBarHeightConstraint != nil, restingBarHeightConstraint.constant != height else { return }
        restingBarHeightConstraint.constant = height
    }

    /// Set the keyboard bar's height to its measured SwiftUI content height. Pinned at the bottom to
    /// the keyboard guide, so growing the constant grows the bar *upward* — it can never push content
    /// below the keyboard.
    public func setKeyboardBarHeight(_ height: CGFloat) {
        guard keyboardBarHeightConstraint != nil, keyboardBarHeightConstraint.constant != height else { return }
        keyboardBarHeightConstraint.constant = height
    }

    /// Switch which bar the transcript reserves bottom inset for, and which one takes touches.
    public func setComposing(_ composing: Bool) {
        guard isComposing != composing else { return }
        isComposing = composing
        applyBarInteraction()
        view.setNeedsLayout()
    }

    /// Only the active bar takes touches. The bars overlap at the bottom when the keyboard is down,
    /// and a hosting controller's view doesn't pass touches through on `.allowsHitTesting(false)`
    /// alone — disabling the inactive bar at the UIKit layer reliably lets the active one receive them.
    private func applyBarInteraction() {
        restingBar.isUserInteractionEnabled = !isComposing
        keyboardBar.isUserInteractionEnabled = isComposing
    }

    // MARK: - Data passthrough

    public func update(items: [ChatItem]) { transcript.update(items: items) }
    public func scrollToBottom(animated: Bool = true) { transcript.scrollToBottom(animated: animated) }

    // MARK: - Bar inset

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Reserve only the active bar's own height. On-device the system already grows the collection
        // view's adjusted content inset by the keyboard when it's up, so adding the keyboard here
        // too (via the bar's risen position) double-counts it and overscrolls by a whole keyboard.
        transcript.setBottomInset(isComposing ? keyboardBar.frame.height : restingBar.frame.height)
    }
}
#endif
