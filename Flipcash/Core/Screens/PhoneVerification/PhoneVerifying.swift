//
//  PhoneVerifying.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Public contract for any phone-verification implementation. Refines
/// `Verifying` with phone-specific state and actions. Hosts that compose
/// a phone verifier (e.g. `OnrampVerificationViewModel`) wire the inherited
/// callbacks; standalone consumers (e.g. a Send-side sheet) `await run()`.
@MainActor
protocol PhoneVerifying: Verifying {
    // MARK: - State -

    var enteredPhone: String { get set }
    var enteredCode: String { get set }
    var region: Region { get }

    var verificationPath: [PhoneVerificationPath] { get set }

    var sendCodeButtonState: ButtonState { get set }
    var confirmCodeButtonState: ButtonState { get set }

    var codeLength: Int { get }

    // MARK: - Derived state -

    var phone: Phone? { get }
    var showsInvalidPhoneHint: Bool { get }
    var regionFlagStyle: Flag.Style { get }
    var countryCode: String { get }
    var canSendVerificationCode: Bool { get }
    var isCodeComplete: Bool { get }

    // MARK: - Bindings -

    var adjustingPhoneNumberBinding: Binding<String> { get }
    var adjustingCodeBinding: Binding<String> { get }

    // MARK: - Actions -

    func setRegion(_ region: Region)
    func sendPhoneNumberCodeAction()
    func resendCodeAction() async throws
    func confirmPhoneNumberCodeAction()
    func pasteCodeFromClipboardIfPossible()
}
