//
//  VerificationViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("VerificationViewModel")
struct VerificationViewModelTests {

    @Test("applyDeeplinkVerification sets the confirm-email path and stashes the email")
    func applyDeeplinkVerification_setsConfirmEmailPath() {
        let viewModel = VerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(viewModel.verificationPath == [.confirmEmailCode])
        #expect(viewModel.enteredEmail == "a@b.c")
    }
}
