//
//  PhoneVerificationViewModel.swift
//  Flipcash
//

import UIKit
import SwiftUI
import FlipcashUI
import FlipcashCore

/// Concrete phone verifier. Conforms to `PhoneVerifying`; the `run`,
/// `cancel`, and `finish` lifecycle is provided by the `Verifying` extension.
@Observable
@MainActor
final class PhoneVerificationViewModel: PhoneVerifying {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [PhoneVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                reset()
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

    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair

    @ObservationIgnored private let phoneFormatter = PhoneFormatter()
    @ObservationIgnored private let phoneValidator = PhoneValidator()

    // MARK: - Analytics hooks -

    /// Fires once when `run()` starts a fresh suspension (standalone mode).
    /// Wrapped callers (e.g. Onramp) leave this nil and fire their own
    /// flavored event at the outer VM's path-mutation site instead.
    @ObservationIgnored private let enterPhoneEvent: (any AnalyticsEvent)?

    /// Fires after `sendPhoneNumberCodeAction` succeeds (standalone mode).
    /// Wrapped callers leave nil — outer's `onCodeRequested` callback fires
    /// its own flavored event there.
    @ObservationIgnored private let confirmPhoneEvent: (any AnalyticsEvent)?

    // MARK: - Profile hooks -

    /// Short-circuit for `Verifying.run()`. Defaults to `false`.
    @ObservationIgnored private let isAlreadyVerifiedProvider: @MainActor () -> Bool

    /// Post-success refresh, awaited before `onVerified` fires. Defaults
    /// to a no-op.
    @ObservationIgnored private let onShouldRefreshProfile: @MainActor () async -> Void

    // MARK: - Verifying lifecycle hooks -

    @ObservationIgnored var onCodeRequested: (@MainActor () -> Void)?
    @ObservationIgnored var onVerified: (@MainActor () -> Void)?

    /// Internal hook for the `Verifying` default `run`/`cancel`/`finish`
    /// implementations. Not for outside callers.
    @ObservationIgnored var continuation: CheckedContinuation<Void, Error>?

    // MARK: - Init -

    init(
        owner: KeyPair,
        flipClient: FlipClient,
        enterPhoneEvent: (any AnalyticsEvent)? = nil,
        confirmPhoneEvent: (any AnalyticsEvent)? = nil,
        isAlreadyVerified: @MainActor @escaping () -> Bool = { false },
        onShouldRefreshProfile: @MainActor @escaping () async -> Void = { },
    ) {
        self.flipClient = flipClient
        self.owner = owner
        self.region = phoneFormatter.currentRegion
        self.enterPhoneEvent = enterPhoneEvent
        self.confirmPhoneEvent = confirmPhoneEvent
        self.isAlreadyVerifiedProvider = isAlreadyVerified
        self.onShouldRefreshProfile = onShouldRefreshProfile
    }

    isolated deinit {
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    func reset() {
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
        phoneValidator.validate(enteredPhone)
    }

    var canSendVerificationCode: Bool {
        phone != nil
    }

    var isCodeComplete: Bool {
        enteredCode.count >= codeLength
    }

    var isAlreadyVerified: Bool {
        isAlreadyVerifiedProvider()
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

        if let enterPhoneEvent {
            Analytics.track(event: enterPhoneEvent)
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
                    if let confirmPhoneEvent {
                        Analytics.track(event: confirmPhoneEvent)
                    }
                }

                try await Task.delay(milliseconds: 500)
            }

            catch is CancellationError {
                return
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

                await onShouldRefreshProfile()

                try await Task.delay(milliseconds: 500)
                confirmCodeButtonState = .success

                try await Task.delay(milliseconds: 500)

                if let onVerified {
                    onVerified()
                } else {
                    finish()
                }

                try await Task.delay(milliseconds: 500)
            } catch is CancellationError {
                return
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
