//
//  VerificationViewModel.swift
//  Flipcash
//

import UIKit
import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.verification-viewmodel")

/// Drives the phone+email verification sheet. One instance per attempt:
/// callers construct a viewmodel, present a sheet bound to it, and `await
/// run()` until verification completes (or the sheet dismisses with cancel).
///
/// `Identifiable` so callers can drive `.sheet(item:)` directly with an
/// optional viewmodel binding — no separate `isPresented` flag needed.
@Observable
@MainActor
final class VerificationViewModel: Identifiable {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                resetTransientState()
            }
        }
    }

    var enteredPhone: String = ""
    var enteredCode: String = ""
    var enteredEmail: String = ""

    private(set) var region: Region
    private(set) var isResending: Bool = false

    var sendCodeButtonState: ButtonState = .normal
    var sendEmailCodeState: ButtonState = .normal
    var confirmCodeButtonState: ButtonState = .normal
    var confirmEmailButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    let codeLength = 6

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    @ObservationIgnored private let phoneFormatter = PhoneFormatter()

    // MARK: - Run continuation -

    @ObservationIgnored private var continuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var deeplinkTask: Task<Void, Never>?

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.region = phoneFormatter.currentRegion
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
        assert(continuation == nil, "VerificationViewModel.run() called while another awaiter is suspended")
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

    var regionFlagStyle: Flag.Style {
        .fiat(region)
    }

    var countryCode: String {
        "+\(phoneFormatter.countryCode(for: region)!)"
    }

    var phone: Phone? {
        Phone(enteredPhone)
    }

    var canSendVerificationCode: Bool {
        phone != nil
    }

    var canSendEmailVerification: Bool {
        isEmailValid
    }

    var isCodeComplete: Bool {
        enteredCode.count >= codeLength
    }

    var isEmailValid: Bool {
        let e = enteredEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !e.isEmpty, e.utf8.count <= 254 else {
            return false
        }

        return e.wholeMatch(of: Self.emailRegex) != nil
    }

    private static let emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }

    private var isAccountVerified: Bool {
        isPhoneVerified && isEmailVerified
    }

    // MARK: - Setters & bindings -

    private func resetTransientState() {
        enteredPhone = ""
        enteredCode = ""
        enteredEmail = ""
        isResending = false
    }

    func setRegion(_ region: Region) {
        self.region = region
    }

    var adjustingPhoneNumberBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredPhone

        } set: { [weak self] newValue in
            guard let self = self else { return }
            let cleanPhoneNumber = newValue.filter { character in
                CharacterSet.numbers.contains(character.unicodeScalars.first!)
            }

            let countryCode = self.phoneFormatter.countryCode(for: self.region)!
            self.enteredPhone = self.phoneFormatter.format("+\(countryCode)\(cleanPhoneNumber)")
        }
    }

    var adjustingCodeBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredCode

        } set: { [weak self] newValue in
            guard let self = self else { return }

            if newValue.count > self.codeLength {
                self.enteredCode = String(newValue.prefix(self.codeLength))
            } else {
                self.enteredCode = newValue
            }
        }
    }

    // MARK: - Clipboard -

    func pasteCodeFromClipboardIfPossible() {
        guard let code = codeFromClipboard() else {
            return
        }

        enteredCode = code
    }

    private func codeFromClipboard() -> String? {
        if let codeString = UIPasteboard.general.string, codeString.count == codeLength {
            let digits: [Int] = codeString.utf8.compactMap { char in
                let digit = Int(char)
                if digit >= 48 && digit <= 57 {
                    return digit
                }
                return nil
            }

            if digits.count == codeLength {
                return codeString
            }
        }
        return nil
    }

    // MARK: - Navigation -

    /// Entry point invoked by `VerifyInfoScreen`'s Next button.
    func navigateToInitialVerification() {
        navigateToAmount(from: .info)
    }

    private func navigateToAmount(from origin: Origin) {
        if origin.rawValue < Origin.phone.rawValue, !isPhoneVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            verificationPath.append(.enterPhoneNumber)
            return
        }

        if origin.rawValue < Origin.email.rawValue, !isEmailVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            verificationPath.append(.enterEmail)
            return
        }

        // Both steps satisfied — resume the caller.
        finish()
    }

    // MARK: - Verification actions -

    func sendPhoneNumberCodeAction() {
        guard let phone else {
            return
        }

        Task {
            sendCodeButtonState = .loading
            defer {
                sendCodeButtonState = .normal
            }

            do {
                try await flipClient.sendVerificationCode(
                    phone: phone.e164,
                    owner: owner
                )
                try await Task.delay(milliseconds: 500)
                sendCodeButtonState = .success

                try await Task.delay(milliseconds: 500)
                verificationPath.append(.confirmPhoneNumberCode)

                Analytics.track(event: Analytics.OnrampEvent.showConfirmPhone)

                try await Task.delay(milliseconds: 500)
            }

            catch
                ErrorSendVerificationCode.invalidPhoneNumber,
                ErrorSendVerificationCode.unsupportedPhoneType
            {
                showUnsupportedPhoneNumberError()
            }

            catch {
                ErrorReporting.captureError(error)
                showGenericError()
            }
        }
    }

    func resendCodeAction() async throws {
        guard let phone else {
            return
        }

        isResending = true
        defer {
            isResending = false
        }

        do {
            try await flipClient.sendVerificationCode(
                phone: phone.e164,
                owner: owner
            )
        } catch {
            ErrorReporting.captureError(error)
        }
    }

    func confirmPhoneNumberCodeAction() {
        guard let phone else {
            return
        }

        guard isCodeComplete else {
            return
        }

        Task {
            confirmCodeButtonState = .loading
            defer {
                confirmCodeButtonState = .normal
            }

            do {
                try await flipClient.checkVerificationCode(
                    phone: phone.e164,
                    code: enteredCode,
                    owner: owner
                )

                try? await session.updateProfile()

                try await Task.delay(milliseconds: 500)
                confirmCodeButtonState = .success

                try await Task.delay(milliseconds: 500)
                navigateToAmount(from: .phone)

                try await Task.delay(milliseconds: 500)
            } catch ErrorCheckVerificationCode.invalidCode {
                showInvalidCodeError()
            } catch ErrorCheckVerificationCode.noVerification {
                showGenericError()
            } catch {
                ErrorReporting.captureError(error)
            }
        }
    }

    func sendEmailCodeAction() {
        guard isEmailValid else {
            return
        }

        Task {
            sendEmailCodeState = .loading
            defer {
                sendEmailCodeState = .normal
            }

            do {
                try await flipClient.sendEmailVerification(
                    email: enteredEmail,
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
        guard isEmailValid else {
            return
        }

        isResending = true
        defer {
            isResending = false
        }

        do {
            try await flipClient.sendEmailVerification(
                email: enteredEmail,
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
        // call `navigateToAmount(from: .email)`, double-finishing.
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
                navigateToAmount(from: .email)
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
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
            .okay(kind: .destructive, action: action)
        }
    }

    private func presentResendOrCancelDialog(title: String, subtitle: String, resendAction: @escaping () -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true,
        ) {
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

    private func showUnsupportedPhoneNumberError() {
        presentDestructiveDialog(
            title: "Unsupported Phone Number",
            subtitle: "Please use a different phone number and try again"
        )
    }

    private func showInvalidEmailError() {
        presentDestructiveDialog(
            title: "Invalid Email",
            subtitle: "Please enter a different email and try again"
        )
    }

    private func showInvalidCodeError() {
        presentDestructiveDialog(
            title: "Invalid Code",
            subtitle: "Please enter the verification code that was sent to your phone number or request a new code"
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

// MARK: - Supporting types -

private enum Origin: Int {
    case info
    case phone
    case email
}

private extension CharacterSet {
    static let numbers: CharacterSet = CharacterSet(charactersIn: "0123456789")
}
