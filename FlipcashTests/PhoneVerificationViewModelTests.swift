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
