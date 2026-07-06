//
//  PhoneVerificationViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("PhoneVerificationViewModel")
struct PhoneVerificationViewModelTests {

    @Test("Formatted input parses to E.164 via the Phone derived property")
    func enteredPhone_parsesToE164() {
        let viewModel = PhoneVerificationViewModel(owner: .mock, flipClient: .mock)
        viewModel.setRegion(.us)
        viewModel.enteredPhone = "+1 415 555 0100"

        #expect(viewModel.canSendVerificationCode)
        #expect(viewModel.phone?.e164 == "+14155550100")
    }

    @Test("A pasted full +1 number is valid, so auto-advance fires")
    func pastedInternationalNumber_isValid() {
        let viewModel = PhoneVerificationViewModel(owner: .mock, flipClient: .mock)
        viewModel.setRegion(.us)

        // A whole-string binding set is exactly what SwiftUI delivers on paste.
        viewModel.adjustingPhoneNumberBinding.wrappedValue = "+1 6138096923"

        #expect(viewModel.canSendVerificationCode)
        #expect(viewModel.phone?.e164 == "+16138096923")
    }

    @Test("A partial number is not valid, so auto-advance stays gated")
    func partialNumber_isNotValid() {
        let viewModel = PhoneVerificationViewModel(owner: .mock, flipClient: .mock)
        viewModel.setRegion(.us)

        viewModel.adjustingPhoneNumberBinding.wrappedValue = "613809"

        #expect(viewModel.canSendVerificationCode == false)
        #expect(viewModel.phone == nil)
    }

    @Test("Default isAlreadyVerified is false — onboarding never short-circuits the phone step")
    func isAlreadyVerified_defaultsFalse() {
        let viewModel = PhoneVerificationViewModel(owner: .mock, flipClient: .mock)
        #expect(viewModel.isAlreadyVerified == false)
    }

    @Test("Caller-supplied isAlreadyVerified closure is consulted")
    func isAlreadyVerified_usesProvider() {
        let verifiedVM = PhoneVerificationViewModel(
            owner: .mock,
            flipClient: .mock,
            isAlreadyVerified: { true },
        )
        let unverifiedVM = PhoneVerificationViewModel(
            owner: .mock,
            flipClient: .mock,
            isAlreadyVerified: { false },
        )
        #expect(verifiedVM.isAlreadyVerified == true)
        #expect(unverifiedVM.isAlreadyVerified == false)
    }
}
