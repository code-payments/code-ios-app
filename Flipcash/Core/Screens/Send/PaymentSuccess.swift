//
//  PaymentSuccess.swift
//  Flipcash
//

import Foundation

/// How a payment sheet finishes once its swipe has succeeded: the checkmark is held, then the
/// sheet is released. Inline flows (swap, convert, add money) keep `InlineCompletion.successHold`.
nonisolated enum PaymentSuccess {

    /// How long the success checkmark stays up on payment and swipe-to-send sheets. Matches Android.
    static let hold: Duration = .seconds(1)

    /// Holds the checkmark, then runs `release`. Skips `release` if the calling task was cancelled
    /// during the hold, so a sheet that closed meanwhile isn't dismissed twice.
    static func release(after hold: Duration = PaymentSuccess.hold, _ release: () -> Void) async {
        try? await Task.sleep(for: hold)
        guard !Task.isCancelled else { return }
        release()
    }
}
