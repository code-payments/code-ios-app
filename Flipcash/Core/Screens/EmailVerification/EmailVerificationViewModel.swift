//
//  EmailVerificationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Concrete email verifier. Conforms to `EmailVerifying`; the `run`,
/// `cancel`, and `finish` lifecycle is provided by the `Verifying` extension.
@Observable
@MainActor
final class EmailVerificationViewModel: EmailVerifying {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [EmailVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                reset()
            }
        }
    }

    var enteredEmail: String = ""

    private(set) var isResending: Bool = false

    var sendEmailCodeState: ButtonState = .normal
    var confirmEmailButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    @ObservationIgnored private let emailValidator = EmailValidator()

    // MARK: - Analytics hooks -

    /// Fires after `sendEmailCodeAction` succeeds (standalone mode).
    /// Wrapped callers leave nil — outer's `onCodeRequested` callback fires
    /// its own flavored event there.
    @ObservationIgnored private let confirmEmailEvent: (any AnalyticsEvent)?

    // MARK: - Verifying lifecycle hooks -

    @ObservationIgnored var onCodeRequested: (@MainActor () -> Void)?
    @ObservationIgnored var onVerified: (@MainActor () -> Void)?

    /// Internal hook for the `Verifying` default `run`/`cancel`/`finish`
    /// implementations. Not for outside callers.
    @ObservationIgnored var continuation: CheckedContinuation<Void, Error>?

    @ObservationIgnored private var deeplinkTask: Task<Void, Never>?

    // MARK: - Init -

    init(
        session: Session,
        flipClient: FlipClient,
        confirmEmailEvent: (any AnalyticsEvent)? = nil
    ) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.confirmEmailEvent = confirmEmailEvent
    }

    isolated deinit {
        deeplinkTask?.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    /// Email VM overrides the default `cancel()` to also cancel the
    /// in-flight deeplink task; the base lifecycle alone wouldn't reach it.
    func cancel() {
        deeplinkTask?.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    func reset() {
        enteredEmail = ""
        isResending = false
    }

    // MARK: - Derived state -

    var validatedEmail: String? {
        emailValidator.validate(enteredEmail)
    }

    var canSendEmailVerification: Bool {
        validatedEmail != nil
    }

    var isAlreadyVerified: Bool {
        session.profile?.isEmailVerified ?? false
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

                if let onCodeRequested {
                    onCodeRequested()
                } else {
                    verificationPath.append(.confirmEmailCode)
                    if let confirmEmailEvent {
                        Analytics.track(event: confirmEmailEvent)
                    }
                }

                try await Task.delay(milliseconds: 500)
            } catch is CancellationError {
                return
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
        guard !isAlreadyVerified else { return }
        // Drop overlapping deeplinks while one is in flight — two concurrent
        // Tasks would fight over `confirmEmailButtonState` and could both
        // call `onVerified` / `finish`, double-finishing.
        guard deeplinkTask == nil else { return }

        enteredEmail = verification.email
        // Standalone mode lands the user on the confirm screen so the API
        // call's result has somewhere to surface. Wrapped mode leaves
        // navigation to the host — the host calls this method *after*
        // setting up its own path.
        if onCodeRequested == nil && verificationPath.last != .confirmEmailCode {
            verificationPath = [.confirmEmailCode]
        }

        deeplinkTask = Task { [weak self] in
            guard let self else { return }
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

                if let onVerified {
                    onVerified()
                } else {
                    finish()
                }
            } catch is CancellationError {
                return
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
