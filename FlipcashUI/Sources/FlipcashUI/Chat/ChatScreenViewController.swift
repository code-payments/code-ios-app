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
/// floats over its bottom (so content flows under it). The bar is pinned to the keyboard layout
/// guide, which rests at the bottom safe area when the keyboard is down and rides it when shown —
/// one bar covers both states. This screen stays agnostic about *what* the bar is and only owns
/// layout + keyboard handling.
///
/// Keyboard handling is deliberately *not* hand-rolled. The host's safe area already grows to
/// include the keyboard, so the bar rides the keyboard for free and the transcript only reserves
/// the bar's own height — the safe area supplies the keyboard. Doing both ourselves was what
/// double-counted the keyboard.
public final class ChatScreenViewController: UIViewController {

    private let transcript = ChatViewController()
    private let bar: UIView
    private let barController: UIViewController?
    /// The bar's height is driven by its *measured* SwiftUI height, so the frame matches its
    /// content exactly — a hosting controller's intrinsic size mis-measures multiline growth and
    /// lets the composer overflow below its frame, under the keyboard.
    private var barHeightConstraint: NSLayoutConstraint!

    /// - Parameters:
    ///   - bar: pinned to the keyboard layout guide; rides the keyboard.
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

        barHeightConstraint = addBar(bar, controller: barController, pinnedTo: view.keyboardLayoutGuide.topAnchor)
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
        // Reserve only the bar's own height. On-device the system already grows the collection
        // view's adjusted content inset by the keyboard when it's up, so adding the keyboard here
        // too (via the bar's risen position) double-counts it and overscrolls by a whole keyboard.
        transcript.setBottomInset(bar.frame.height)
    }
}
#endif
