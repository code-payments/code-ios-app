//
//  PhoneVerificationViewModel.swift
//  Flipcash
//

import UIKit
import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.phone-verification-viewmodel")

/// Drives the phone verification flow. Used standalone via
/// `PhoneVerificationFlowScreen` or wrapped by `OnrampVerificationViewModel`
/// which composes it with email + KYC info.
///
/// In standalone mode, callers `await run()` and the viewmodel manages its
/// own `verificationPath` + resumes the continuation on success.
///
/// In wrapped mode, the host sets `onCodeRequested` and `onVerified`
/// callbacks; the viewmodel fires them instead of mutating its own path or
/// resuming a continuation. The host drives the navigation stack and the
/// continuation lifecycle.
@Observable
@MainActor
final class PhoneVerificationViewModel: Identifiable {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [PhoneVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                resetTransientState()
            }
        }
    }

    var enteredPhone: String = ""
    var enteredCode: String = ""

    private(set) var region: Region
    private(set) var isResending: Bool = false

    var sendCodeButtonState: ButtonState = .normal
    var confirmCodeButtonState: ButtonState = .normal

    var dialogItem: DialogItem?

    let codeLength = 6

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    @ObservationIgnored private let phoneFormatter = PhoneFormatter()

    // MARK: - Wrapped-mode hooks -

    /// Fired after `sendPhoneNumberCodeAction` succeeds. When set, replaces
    /// the standalone-mode `verificationPath.append(.confirmPhoneNumberCode)`
    /// so the host can advance its own path instead.
    @ObservationIgnored var onCodeRequested: (() -> Void)?

    /// Fired after `confirmPhoneNumberCodeAction` succeeds. When set, replaces
    /// the standalone-mode `finish()` call so the host can advance to its
    /// next step (e.g. email) instead of resuming an awaited `run()`.
    @ObservationIgnored var onVerified: (() -> Void)?

    // MARK: - Run continuation -

    @ObservationIgnored private var continuation: CheckedContinuation<Void, Error>?

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.region = phoneFormatter.currentRegion
    }

    isolated deinit {
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    // MARK: - Async entry -

    /// Suspends until phone verification completes, then returns. Standalone
    /// mode only — in wrapped mode the host owns the awaited lifecycle and
    /// this is never called.
    func run() async throws {
        if isPhoneVerified { return }
        assert(continuation == nil, "PhoneVerificationViewModel.run() called while another awaiter is suspended")
        guard continuation == nil else { throw CancellationError() }
        try await withCheckedThrowingContinuation { c in
            continuation = c
        }
    }

    /// Idempotent. Resumes a pending `run()` with `CancellationError`. Safe
    /// to call in wrapped mode (no continuation to resume, no-op).
    func cancel() {
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    private func finish() {
        let c = continuation
        continuation = nil
        c?.resume()
    }

    func resetTransientState() {
        enteredPhone = ""
        enteredCode = ""
        isResending = false
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

    var isCodeComplete: Bool {
        enteredCode.count >= codeLength
    }

    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    // MARK: - Setters & bindings -

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

                if let onCodeRequested {
                    onCodeRequested()
                } else {
                    verificationPath.append(.confirmPhoneNumberCode)
                }

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

                if let onVerified {
                    onVerified()
                } else {
                    finish()
                }

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

    private func showInvalidCodeError() {
        presentDestructiveDialog(
            title: "Invalid Code",
            subtitle: "Please enter the verification code that was sent to your phone number or request a new code"
        )
    }
}

private extension CharacterSet {
    static let numbers: CharacterSet = CharacterSet(charactersIn: "0123456789")
}
