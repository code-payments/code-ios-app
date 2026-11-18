//
//  FocusAfterPush.swift
//  FlipcashUI
//

import SwiftUI
import UIKit

extension View {

    /// Focuses `focus` once when this screen is pushed or presented, during the transition when a
    /// keyboard is already up and after it finishes otherwise, and not again after Back.
    public func focusAfterPush(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(FocusAfterPushModifier(focus: focus))
    }
}

private struct FocusAfterPushModifier: ViewModifier {

    let focus: FocusState<Bool>.Binding

    @State private var hasFocused = false

    func body(content: Content) -> some View {
        content.background {
            if !hasFocused {
                TransitionEndProbe {
                    hasFocused = true
                    focus.wrappedValue = true
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }
}

/// Calls `onSettled` once the transition showing this view has finished, or as soon as the view
/// appears when no transition is running or a keyboard was up as the view was built.
private struct TransitionEndProbe: UIViewControllerRepresentable {

    let onSettled: () -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        // Read as the screen is built: by the time it appears, the push has already resigned the
        // previous screen's field, and whether the keyboard's will-hide has landed yet varies.
        ProbeController(keyboardWasUp: KeyboardVisibility.shared.isVisible)
    }

    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.onSettled = onSettled
    }

    final class ProbeController: UIViewController {

        var onSettled: (() -> Void)?

        private let keyboardWasUp: Bool
        private var hasSettled = false

        init(keyboardWasUp: Bool) {
            self.keyboardWasUp = keyboardWasUp
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            guard !hasSettled else { return }
            // Focusing during the push hands the keyboard to this screen's field before the
            // previous field's resign takes it down, so the keyboard changes type in place.
            if keyboardWasUp {
                settle()
                return
            }
            // Reaches the push or presentation in flight through the parent controllers. Read any
            // earlier and it can still be nil for a push that is about to start.
            guard let coordinator = transitionCoordinator else {
                settle()
                return
            }
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else { return }
                self?.settle()
            }
        }

        private func settle() {
            // A screen popped before its push finished has left the window; don't focus it.
            guard !hasSettled, viewIfLoaded?.window != nil else { return }
            hasSettled = true
            onSettled?()
        }
    }
}

/// Whether the software keyboard is on screen, from its will-show and will-hide notifications.
///
/// Observes from first use, so a keyboard raised before any `focusAfterPush` screen was built
/// reads as hidden. A hardware keyboard posts neither notification and also reads as hidden.
private final class KeyboardVisibility {

    static let shared = KeyboardVisibility()

    private(set) var isVisible = false

    private init() {
        let changes = [
            (UIResponder.keyboardWillShowNotification, true),
            (UIResponder.keyboardWillHideNotification, false),
        ]
        for (name, isVisible) in changes {
            // Handled on the posting thread (UIKit posts these on the main one): a hop through a
            // Task could land after the next push has already read the value.
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isVisible = isVisible
                }
            }
        }
    }
}
