//
//  EmailVerificationViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("EmailVerificationViewModel")
struct EmailVerificationViewModelTests {

    @Test("applyDeeplinkVerification parks the user on confirmEmail and stashes the email")
    func applyDeeplinkVerification_setsConfirmEmailPath() {
        let viewModel = EmailVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(viewModel.verificationPath == [.confirmEmailCode])
        #expect(viewModel.enteredEmail == "a@b.c")
    }
}
