//
//  EdgeOnlySwipeBack.swift
//  Flipcash
//

import SwiftUI
import UIKit

extension View {

    /// Constrains a sheet-hosted `NavigationStack`'s swipe-to-go-back gesture to
    /// begin only near the leading edge, matching the root stack's behavior.
    ///
    /// A `NavigationStack` presented inside a `.sheet` otherwise recognizes its
    /// interactive-pop gesture from anywhere on screen (center, buttons, the back
    /// button) — a UIKit asymmetry SwiftUI inherits for modally presented stacks.
    /// Apply on the root content view of each sheet-hosted `NavigationStack`.
    func edgeOnlySwipeBack(edgeWidth: CGFloat = 30) -> some View {
        background(EdgeOnlySwipeBack(edgeWidth: edgeWidth))
    }
}

/// Installs a leading-edge gate on the enclosing navigation controller's
/// interactive-pop gesture. The invisible proxy view controller exists only to
/// reach the `UINavigationController` SwiftUI creates for the `NavigationStack`.
private struct EdgeOnlySwipeBack: UIViewControllerRepresentable {

    let edgeWidth: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(edgeWidth: edgeWidth) }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.proxy
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.edgeWidth = edgeWidth
        context.coordinator.install()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        let proxy = ProxyViewController()
        var edgeWidth: CGFloat

        init(edgeWidth: CGFloat) {
            self.edgeWidth = edgeWidth
            super.init()
            proxy.onAttach = { [weak self] in self?.install() }
        }

        func install() {
            guard let nav = navigationController else { return }
            // A sheet-hosted stack carries *two* interactive-pop pan recognizers
            // on its view; `interactivePopGestureRecognizer` is only one of them,
            // and the untouched twin is what pops from the full width. Gate every
            // pop pan-recognizer so the leading-edge rule governs all of them.
            for recognizer in nav.view.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer {
                recognizer.delegate = self
            }
        }

        private var navigationController: UINavigationController? {
            var parent = proxy.parent
            while let candidate = parent {
                if let nav = candidate as? UINavigationController { return nav }
                parent = candidate.parent
            }
            return proxy.navigationController
        }

        // Only track a touch that starts within the leading-edge strip, so a
        // drag from the center of the screen, a button, or the back button no
        // longer begins the pop.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view else { return true }
            let x = touch.location(in: view).x
            switch view.effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                return x >= view.bounds.width - edgeWidth
            case .leftToRight:
                return x <= edgeWidth
            @unknown default:
                return x <= edgeWidth
            }
        }

        // Never pop the root — a full-width swipe at the first screen otherwise
        // wedges navigation (the classic delegate-override bug).
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

/// Reports back once it is attached to (or appears within) the view-controller
/// hierarchy, so the enclosing navigation controller can be resolved.
private final class ProxyViewController: UIViewController {

    var onAttach: (() -> Void)?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        onAttach?()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onAttach?()
    }
}
