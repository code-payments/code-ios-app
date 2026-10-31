//
//  KeyboardHideWaiter.swift
//  Flipcash
//

import UIKit

/// Runs `resign` and returns once the keyboard has finished leaving, so nothing presented next
/// rises while a keyboard is still on screen. It waits on `keyboardWillHide` plus its whole
/// animation rather than `keyboardDidHide`, which lands later still. A hardware keyboard posts
/// neither, so it gives up after `timeout`.
@MainActor
final class KeyboardHideWaiter {
    /// The share of the hide animation to wait out: all of it, so no keyboard pixels remain.
    private static let visibleShare = 1.0

    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: NSObjectProtocol?

    func wait(timeout: Duration = .milliseconds(450), resign: () -> Void) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
                MainActor.assumeIsolated { self?.finish(after: .seconds(duration * Self.visibleShare)) }
            }
            resign()
            finish(after: timeout)
        }
    }

    private func finish(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.finish()
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation.resume()
    }
}
