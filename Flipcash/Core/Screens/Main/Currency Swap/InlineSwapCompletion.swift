//
//  InlineSwapCompletion.swift
//  Flipcash
//

import SwiftUI
import UserNotifications
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.inline-swap-completion")

// MARK: - InlineCompletion -

/// Timing for finishing a swap on the screen that submitted it. The same numbers
/// drive the Android app, so change them in both places.
nonisolated enum InlineCompletion {

    /// Delay between polls while the source screen waits in place.
    static let pollInterval: Duration = .milliseconds(250)

    /// How long the source screen waits before handing over to the processing screen.
    static let window: Duration = .seconds(5)

    /// Polls that fit in `window` at the fast interval.
    static let maxAttempts = Int(window / pollInterval)

    /// The window expressed in the processing screen's one-second polls; its budget shrinks by
    /// this much so total wall time stays what it was before the inline window.
    static let slowPathCredit = Int(window / .seconds(1))

    /// How long the confirm button shows its success state before the flow dismisses.
    static let successHold: Duration = .milliseconds(400)
}

// MARK: - SwapPoller -

/// Polls a swap until it is terminal or `maxAttempts` polls `interval` apart have run.
typealias SwapPoller = (_ maxAttempts: Int, _ interval: Duration) async throws -> SwapMetadata

// MARK: - SwapCompletionReporter -

/// Analytics and error reporting for a finished buy or convert, shared by the inline path
/// and the processing screen so both emit identical events.
struct SwapCompletionReporter {
    let swapId: SwapId
    let swapType: SwapType
    let amount: ExchangedFiat

    /// `Token Purchase` or `Token Sell` for a submitted swap, sent once per submit as Android
    /// sends it, not when the swap finishes. A convert is a sell of its source in every
    /// direction. `mint` is the token bought, or a convert's source; `amount` and `fee` are the
    /// net amount and the fee. A cancelled submit sends nothing.
    static func trackSubmit(swapType: SwapType, mint: PublicKey, amount: ExchangedFiat, fee: ExchangedFiat, error: Error?) {
        if error is CancellationError { return }
        switch swapType {
        case .buyWithReserves:
            Analytics.tokenPurchase(method: .reserves, mint: mint, amount: amount.nativeAmount, error: error)
        case .buyWithCurrency:
            Analytics.tokenPurchase(method: .currency, mint: mint, amount: amount.nativeAmount, error: error)
        case .convert:
            Analytics.tokenSell(mint: mint, amount: amount.nativeAmount, fee: fee.nativeAmount, error: error)
        }
    }

    /// Reports a permanent poll refusal (denied or rejected), which the server will never recover from.
    func reportPollRefusal(_ error: ClientError) {
        logger.error("Swap poll refused", metadata: [
            "swapId": "\(swapId.publicKey.base58)",
            "swapType": "\(swapType)",
            "error": "\(error)",
        ])
        ErrorReporting.captureError(
            error,
            reason: "Swap poll refused by server",
            metadata: [
                "swapId": swapId.publicKey.base58,
                "swapType": "\(swapType)",
                "amount": amount.nativeAmount.formatted(),
                "quarks": "\(amount.onChainAmount.quarks)",
            ]
        )
    }

    func reportSwapFailure(state: SwapState, reason: String) {
        logger.error("Swap failed", metadata: [
            "swapId": "\(swapId.publicKey.base58)",
            "swapType": "\(swapType)",
            "state": "\(state)",
            "reason": "\(reason)",
        ])
        ErrorReporting.captureError(
            SwapError.failed(state: state),
            reason: reason,
            metadata: [
                "swapId": swapId.publicKey.base58,
                "swapType": "\(swapType)",
                "finalState": "\(state)",
                "amount": amount.nativeAmount.formatted(),
                "quarks": "\(amount.onChainAmount.quarks)",
            ]
        )
    }
}

// MARK: - InlineSwapCompletion -

/// Waits for a just-submitted buy or convert on the screen that submitted it.
struct InlineSwapCompletion {

    enum Outcome: Equatable {
        /// The swap finalized; success analytics already fired.
        case succeeded
        /// The swap failed or was cancelled; failure analytics and error reporting already fired.
        case failed
        /// Not terminal within the window; nothing was reported and the processing screen takes over.
        case pending
    }

    let reporter: SwapCompletionReporter
    let poll: SwapPoller

    /// Polls for the inline window and reports a terminal result.
    func awaitOutcome() async -> Outcome {
        do {
            let metadata = try await poll(InlineCompletion.maxAttempts, InlineCompletion.pollInterval)
            switch metadata.state {
            case .finalized:
                return .succeeded
            case .failed, .cancelled:
                reporter.reportSwapFailure(state: metadata.state, reason: "Swap completed with failure state")
                return .failed
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                return .pending
            }
        } catch is CancellationError {
            // The swap is already submitted, so a cancelled wait must not read as a
            // failure that invites a second submit; the processing screen resumes it.
            return .pending
        } catch ClientError.pollLimitReached {
            // No state was ever fetched, which is an unknown state rather than a failure.
            return .pending
        } catch let error as ClientError where error.isSwapPollRefusal {
            reporter.reportPollRefusal(error)
            return .failed
        } catch {
            logger.error("Swap polling failed", metadata: ["error": "\(error)"])
            return .failed
        }
    }
}

// MARK: - InlineSuccess -

/// The shared tail of a fast-path success: the button's success state, then the dismissal.
@MainActor
enum InlineSuccess {

    /// Shows `.success` on the button for `hold`, refreshes post-transaction state, runs
    /// `finish` (the flow's dismissal or hand-off), then asks for the notifications prompt.
    /// The request is only held; ``TransactionNotificationPromptHost`` presents it once the
    /// sheet `finish` closed has finished dismissing.
    static func complete(
        hold: Duration = InlineCompletion.successHold,
        setButtonState: (ButtonState) -> Void,
        updatePostTransaction: () -> Void,
        finish: () async -> Void,
        prompt: TransactionNotificationPrompt
    ) async {
        setButtonState(.success)
        try? await Task.sleep(for: hold)
        updatePostTransaction()
        await finish()
        prompt.request()
    }
}

// MARK: - TransactionNotificationPrompt -

/// Holds a request to offer notifications after a transaction finished in place, until the
/// app-level host can present it. Only a flow that exits after an in-place success requests
/// it; the processing screen carries its own "Notify Me When Complete".
@Observable
@MainActor
final class TransactionNotificationPrompt {

    /// Whether a request is waiting to be presented.
    private(set) var pending = false

    /// Records that the flow just exited after an in-place success.
    func request() {
        pending = true
    }

    /// Takes the waiting request, returning whether there was one.
    func consume() -> Bool {
        defer { pending = false }
        return pending
    }
}

// MARK: - NotificationPrompt -

/// A one-time explainer, shown after a fast-path success, that offers the system
/// notification prompt the processing screen's "Notify Me" button used to carry.
struct NotificationPrompt {

    static let shownKey = "flipcash-transaction-notify-prompt-shown"

    var defaults: UserDefaults = .standard
    var status: () async -> UNAuthorizationStatus = { await PushController.fetchStatus().authorizationStatus }
    var authorize: () async -> Void = { _ = try? await PushController.authorizeAndRegister() }

    var hasShown: Bool { defaults.bool(forKey: Self.shownKey) }

    /// Presents the explainer when push authorization is undetermined and it has never been
    /// shown; "Not Now" and dismissal both count as shown.
    @MainActor
    func presentIfNeeded(present: (DialogItem) -> Void) async {
        guard !hasShown else { return }
        switch await status() {
        case .notDetermined:
            break
        case .denied, .authorized, .provisional, .ephemeral:
            return
        @unknown default:
            return
        }
        defaults.set(true, forKey: Self.shownKey)
        let authorize = authorize
        present(.info(
            title: "Get Notified",
            subtitle: "We'll let you know when your transactions complete, even if you leave the app",
            actions: {
                .standard("Turn On Notifications") { Task { await authorize() } };
                .notNow()
            }
        ))
    }
}
