//
//  OnrampVerificationViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("OnrampVerificationViewModel")
struct OnrampVerificationViewModelTests {

    @Test("applyDeeplinkVerification forwards to the inner email VM and resets Onramp's path")
    func applyDeeplinkVerification_forwardsAndSetsPath() {
        let viewModel = OnrampVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(viewModel.verificationPath == [.confirmEmailCode])
        #expect(viewModel.emailVerifier.enteredEmail == "a@b.c")
    }
}
