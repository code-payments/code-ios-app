//
//  FocusAfterPush.swift
//  FlipcashUI
//

import SwiftUI
import UIKit

extension View {

    /// Focuses `focus` once the push or presentation that brought this screen in has finished, and
    /// not again when the screen comes back into view after Back.
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
/// appears when no transition is running.
private struct TransitionEndProbe: UIViewControllerRepresentable {

    let onSettled: () -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        ProbeController()
    }

    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.onSettled = onSettled
    }

    final class ProbeController: UIViewController {

        var onSettled: (() -> Void)?

        private var hasSettled = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            guard !hasSettled else { return }
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
