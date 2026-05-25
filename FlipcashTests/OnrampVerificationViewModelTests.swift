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

    @Test("applyDeeplinkVerification sets the confirm-email path and stashes the email")
    func applyDeeplinkVerification_setsConfirmEmailPath() {
        let viewModel = OnrampVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(viewModel.verificationPath == [.confirmEmailCode])
        #expect(viewModel.enteredEmail == "a@b.c")
    }
}
