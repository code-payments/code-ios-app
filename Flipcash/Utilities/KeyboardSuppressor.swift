//
//  KeyboardSuppressor.swift
//  Flipcash
//

import UIKit
import FlipcashCore

/// Bars the keyboard for a short window.
///
/// A link tapped while the app is backgrounded is delivered *before* the scene
/// finishes activating, and UIKit restores the first responder the user left
/// focused — a chat's composer, say — as part of that activation. Lowering the
/// keyboard once as the link is routed is therefore undone a moment later, and
/// UIKit publishes no ordering between the two to schedule against. So rather
/// than lowering once, this keeps lowering for as long as the window is open:
/// the restore loses however the two land.
@MainActor
final class KeyboardSuppressor {

    /// How long the keyboard stays barred, in milliseconds.
    private let window: Int

    /// The dismissal itself. Injected so tests can count it.
    private let lower: () -> Void

    private var observer: (any NSObjectProtocol)?
    private var expiry: Task<Void, Never>?

    /// - Parameters:
    ///   - windowMilliseconds: must outlast the scene activation that restores
    ///     the first responder, and close before anything the routing lands on
    ///     can legitimately ask for a keyboard of its own.
    ///   - lower: overridden only by tests.
    init(windowMilliseconds: Int = 1500, lower: (() -> Void)? = nil) {
        self.window = windowMilliseconds
        self.lower = lower ?? { Self.lower() }
    }

    /// Takes the keyboard down once, without barring it from coming back.
    ///
    /// Enough on its own wherever the keyboard belongs to a screen the user is
    /// being routed away from and nothing is racing to restore it. Resigning
    /// first responder is what lowers the keyboard on this platform, so unlike
    /// Compose's `hide()` there is no focused field left for the system to
    /// raise it from again.
    static func lower() {
        // Targets whatever holds focus, so it needs no window reference — a
        // link can be routed before one is key.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    isolated deinit {
        close()
    }

    /// Lowers the keyboard now and bars it for the window. A call made while a
    /// window is already open only re-lowers — it does not extend the bar, so
    /// the scanner re-entering the tip flow on every decoded frame can't hold
    /// the keyboard down indefinitely.
    func suppress() {
        lower()
        guard observer == nil else { return }

        // Handled on the posting thread (UIKit posts keyboard notifications on
        // the main one) rather than hopped through a `Task`: a hop lands a
        // runloop late, by which point the keyboard has begun animating in.
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lower() }
        }

        expiry = Task { [weak self, window] in
            try? await Task.delay(milliseconds: window)
            self?.close()
        }
    }

    private func close() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        expiry?.cancel()
        expiry = nil
    }
}
