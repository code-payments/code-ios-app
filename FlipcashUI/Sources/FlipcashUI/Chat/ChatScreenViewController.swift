//
//  ChatScreenViewController.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// The full chat screen, entirely in UIKit: the transcript fills the view and an injected bar
/// floats over its bottom (so content flows under it). The bar is supplied by the owner — a
/// `ChatComposerBar` in the demo, a hosted SwiftUI Send Cash bar in the app — so this screen
/// stays agnostic about *what* the bar is and only owns layout + keyboard handling.
///
/// Keyboard handling is deliberately *not* hand-rolled. The host's safe area already grows to
/// include the keyboard, so the bar is pinned to the keyboard layout guide (it rides the keyboard
/// for free) and the transcript only reserves the bar's own height — the safe area supplies the
/// keyboard. Doing both ourselves was what double-counted the keyboard.
public final class ChatScreenViewController: UIViewController {

    private let transcript = ChatViewController()
    private let barView: UIView
    private let barViewController: UIViewController?
    /// Driven by the bar's *measured* SwiftUI height (`setBarHeight`), so the bar's frame matches its
    /// content exactly — a hosting controller's intrinsic size mis-measures multiline growth and lets
    /// the composer overflow below its frame, under the keyboard.
    private var barHeightConstraint: NSLayoutConstraint!

    /// - Parameters:
    ///   - barView: the view pinned over the transcript's bottom, riding the keyboard.
    ///   - barViewController: the view controller owning `barView`, when it's hosted (e.g. a
    ///     `UIHostingController` for a SwiftUI bar). Adopted as a child so its lifecycle and
    ///     environment work. Pass `nil` for a plain `UIView` bar.
    public init(barView: UIView, barViewController: UIViewController? = nil) {
        self.barView = barView
        self.barViewController = barViewController
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

        if let barViewController { addChild(barViewController) }
        barView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(barView)
        barViewController?.didMove(toParent: self)

        barHeightConstraint = barView.heightAnchor.constraint(equalToConstant: 80)
        NSLayoutConstraint.activate([
            transcript.view.topAnchor.constraint(equalTo: view.topAnchor),
            transcript.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transcript.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transcript.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            barView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // The keyboard layout guide tracks the keyboard (interactively too), so the bar rides
            // it automatically; when the keyboard is down the guide rests at the bottom safe area.
            barView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            barHeightConstraint,
        ])
    }

    /// Set the bar's height to its measured SwiftUI content height. Pinned at the bottom to the
    /// keyboard guide, so growing the constant grows the bar *upward* — it can never push content
    /// below the keyboard.
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
        transcript.setBottomInset(barView.frame.height)
    }
}
#endif
