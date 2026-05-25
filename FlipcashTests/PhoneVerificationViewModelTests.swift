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
        let viewModel = PhoneVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.setRegion(.us)
        viewModel.enteredPhone = "+1 415 555 0100"

        #expect(viewModel.canSendVerificationCode)
        #expect(viewModel.phone?.e164 == "+14155550100")
    }
}
