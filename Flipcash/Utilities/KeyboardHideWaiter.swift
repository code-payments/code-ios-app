//
//  KeyboardHideWaiter.swift
//  Flipcash
//

import UIKit

/// Runs `resign` and returns once the keyboard is out of sight. `keyboardDidHide` lands well after
/// that, since the hide is a spring whose tail runs on unseen below the screen, so this waits on
/// `keyboardWillHide` plus part of its animation instead. A hardware keyboard posts neither, so it
/// gives up after `timeout`.
@MainActor
final class KeyboardHideWaiter {
    /// The share of the hide animation after which the keyboard is visually gone.
    private static let visibleShare = 0.6

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
