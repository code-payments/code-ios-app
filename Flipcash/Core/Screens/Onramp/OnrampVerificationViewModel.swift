//
//  OnrampVerificationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onramp-verification-viewmodel")

/// Drives the Coinbase onramp KYC flow: phone verification → email
/// verification → KYC info collection. Composes a `PhoneVerificationViewModel`
/// for the phone half and adds the email + deeplink machinery on top.
///
/// `Identifiable` so callers can drive `.sheet(item:)` directly with an
/// optional viewmodel binding — no separate `isPresented` flag needed.
@Observable
@MainActor
final class OnrampVerificationViewModel: Identifiable {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                resetTransientState()
                phoneViewModel.resetTransientState()
            }
        }
    }

    var enteredEmail: String = ""

    private(set) var isResending: Bool = false

    var sendEmailCodeState: ButtonState = .normal
    var confirmEmailButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    // MARK: - Composed phone verification -

    let phoneViewModel: PhoneVerificationViewModel

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    @ObservationIgnored private let emailValidator = EmailValidator()

    // MARK: - Run continuation -

    @ObservationIgnored private var continuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var deeplinkTask: Task<Void, Never>?

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.phoneViewModel = PhoneVerificationViewModel(session: session, flipClient: flipClient)

        phoneViewModel.onCodeRequested = { [weak self] in
            guard let self else { return }
            verificationPath.append(.confirmPhoneNumberCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmPhone)
        }
        phoneViewModel.onVerified = { [weak self] in
            self?.navigateToEmailOrFinish()
        }
    }

    isolated deinit {
        // Failsafe: a viewmodel discarded mid-flow without an explicit cancel
        // would otherwise leave the caller's `await run()` suspended forever.
        deeplinkTask?.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    // MARK: - Async entry -

    /// Suspends until both phone and email are verified, then returns.
    /// Throws `CancellationError` if `cancel()` fires (user dismisses the
    /// sheet). Returns immediately if the profile is already fully verified.
    /// Must not be called concurrently on the same viewmodel — assertion
    /// fires in debug; in release the new call resumes with `CancellationError`
    /// so the caller observes a consistent failure rather than hanging.
    func run() async throws {
        if isAccountVerified { return }
        assert(continuation == nil, "OnrampVerificationViewModel.run() called while another awaiter is suspended")
        guard continuation == nil else { throw CancellationError() }
        try await withCheckedThrowingContinuation { c in
            continuation = c
        }
    }

    /// Idempotent. Called by the sheet host when the user dismisses the
    /// verification sheet, or directly by callers that want to tear down
    /// the flow. Resumes a pending `run()` with `CancellationError`.
    func cancel() {
        deeplinkTask?.cancel()
        deeplinkTask = nil
        phoneViewModel.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    private func finish() {
        let c = continuation
        continuation = nil
        c?.resume()
    }

    // MARK: - Derived state -

    var validatedEmail: String? {
        emailValidator.validate(enteredEmail)
    }

    var canSendEmailVerification: Bool {
        validatedEmail != nil
    }

    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }

    private var isAccountVerified: Bool {
        isPhoneVerified && isEmailVerified
    }

    // MARK: - Setters -

    private func resetTransientState() {
        enteredEmail = ""
        isResending = false
    }

    // MARK: - Navigation -

    /// Entry point invoked by `VerifyInfoScreen`'s Next button.
    func navigateToInitialVerification() {
        if !isPhoneVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            verificationPath.append(.enterPhoneNumber)
            return
        }

        navigateToEmailOrFinish()
    }

    private func navigateToEmailOrFinish() {
        if !isEmailVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            verificationPath.append(.enterEmail)
            return
        }

        finish()
    }

    // MARK: - Verification actions -

    func sendEmailCodeAction() {
        guard let validatedEmail else {
            return
        }

        Task {
            sendEmailCodeState = .loading
            defer {
                sendEmailCodeState = .normal
            }

            do {
                try await flipClient.sendEmailVerification(
                    email: validatedEmail,
                    owner: owner
                )
                try await Task.delay(milliseconds: 500)
                sendEmailCodeState = .success

                try await Task.delay(milliseconds: 500)
                verificationPath.append(.confirmEmailCode)

                Analytics.track(event: Analytics.OnrampEvent.showConfirmEmail)

                try await Task.delay(milliseconds: 500)
            } catch ErrorSendEmailCode.invalidEmailAddress {
                showInvalidEmailError()
            } catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }

    func resendEmailCodeAction() async throws {
        guard let validatedEmail else {
            return
        }

        isResending = true
        defer {
            isResending = false
        }

        do {
            try await flipClient.sendEmailVerification(
                email: validatedEmail,
                owner: owner
            )
        } catch {
            ErrorReporting.captureError(error)
        }
    }

    func applyDeeplinkVerification(_ verification: VerificationDescription) {
        guard !isEmailVerified else { return }
        // Drop overlapping deeplinks while one is in flight — two concurrent
        // Tasks would fight over `confirmEmailButtonState` and could both
        // call `navigateToEmailOrFinish()`, double-finishing.
        guard deeplinkTask == nil else { return }

        // Park the user on the confirm-code screen so the API call's result
        // has somewhere to surface. When the viewmodel was just constructed
        // by the deeplink router (out-of-flow case), the path is empty —
        // initialize it here.
        if verificationPath.last != .confirmEmailCode {
            verificationPath = [.confirmEmailCode]
            enteredEmail = verification.email
        }

        deeplinkTask = Task {
            confirmEmailButtonState = .loading
            defer {
                confirmEmailButtonState = .normal
                deeplinkTask = nil
            }

            do {
                try await flipClient.checkEmailCode(
                    email: verification.email,
                    code: verification.code,
                    owner: owner
                )

                try? await session.updateProfile()

                try await Task.delay(milliseconds: 500)
                confirmEmailButtonState = .success

                try await Task.delay(milliseconds: 500)
                navigateToEmailOrFinish()
            } catch ErrorCheckEmailCode.invalidCode {
                showInvalidVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                }
            } catch ErrorCheckEmailCode.noVerification {
                showExpiredVerificationLinkError { [weak self] in
                    Task {
                        try await self?.resendEmailCodeAction()
                    }
                }
            } catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }

    // MARK: - Dialog factories -

    private func presentDestructiveDialog(
        title: String,
        subtitle: String,
        action: @escaping DialogAction.DialogActionHandler = {}
    ) {
        dialogItem = .error(title: title, subtitle: subtitle) {
            .okay(kind: .destructive, action: action)
        }
    }

    private func presentResendOrCancelDialog(title: String, subtitle: String, resendAction: @escaping () -> Void) {
        dialogItem = .error(title: title, subtitle: subtitle) {
            .destructive("Resend Verification Code") {
                resendAction()
            };
            .cancel()
        }
    }

    private func showGenericError(action: @escaping DialogAction.DialogActionHandler = {}) {
        presentDestructiveDialog(
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            action: action
        )
    }

    private func showInvalidEmailError() {
        presentDestructiveDialog(
            title: "Invalid Email",
            subtitle: "Please enter a different email and try again"
        )
    }

    private func showInvalidVerificationLinkError(resendAction: @escaping () -> Void) {
        presentResendOrCancelDialog(
            title: "Verification Link Invalid",
            subtitle: "This verification link is invalid. Please try again",
            resendAction: resendAction
        )
    }

    private func showExpiredVerificationLinkError(resendAction: @escaping () -> Void) {
        presentResendOrCancelDialog(
            title: "Verification Link Expired",
            subtitle: "This verification link has expired. Please try again",
            resendAction: resendAction
        )
    }
}
