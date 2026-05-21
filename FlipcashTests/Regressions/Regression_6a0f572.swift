//
//  Regression_6a0f572.swift
//  Flipcash
//
//  Reported as: FlipcashCore.ErrorSendEmailCode.unknown (-1) from
//               VerificationViewModel.sendEmailCodeAction() (the file was
//               named OnrampCoordinator.sendEmailCodeAction() on 1.9.0).
//
//  Symptom:  The client email regex accepted inputs the server's PGV rule
//            rejected, and the gate ran against a trimmed copy while the
//            wire received the raw value — so trailing whitespace alone
//            reproduced the bug. EmailService funneled every gRPC failure
//            into .unknown, surfacing as a generic dialog + Bugsnag noise.
//
//  Fix:      `EmailValidator` in FlipcashCore enforces the proto regex
//            and returns the trimmed canonical form; the viewmodel's send
//            paths route through it so the wire receives the validated
//            value, not the raw input. EmailService maps gRPC
//            invalid_argument to `.invalidEmailAddress` so the user sees
//            the right dialog and Bugsnag stops collecting noise.
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("Regression: 6a0f572 – Email regex/trim divergence sent invalid emails to the server", .bug("6a0f57258c3285d1a5b3195c"))
struct Regression_6a0f572 {

    @Test("Whitespace-padded input is trimmed before reaching the wire")
    func trailingWhitespace_isTrimmedBeforeSend() {
        let viewModel = VerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.enteredEmail = "  test@example.com\n"

        #expect(viewModel.canSendEmailVerification)
        #expect(EmailValidator().validate(viewModel.enteredEmail) == "test@example.com")
    }

    @Test("Inputs the proto regex rejects no longer pass the Next gate", arguments: [
        "underscore@my_corp.com",  // domain underscore (server disallows)
        "short@bar.x",             // single-letter TLD
        "numeric@bar.123",         // numeric TLD
        "unicode@café.com",        // non-ASCII domain
    ])
    func serverRejectedInputs_failClientGate(input: String) {
        let viewModel = VerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.enteredEmail = input

        #expect(!viewModel.canSendEmailVerification)
    }
}
