//
//  OnrampCoordinatorTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("OnrampCoordinator")
struct OnrampCoordinatorTests {

    @Test("cancel clears order and verification state")
    func cancelClearsState() {
        let onrampCoordinator = OnrampCoordinator(session: .mock, flipClient: .mock)
        onrampCoordinator.cancel()
        #expect(onrampCoordinator.coinbaseOrder == nil)
        #expect(onrampCoordinator.completion == nil)
    }

    @Test("start with a verified user does not open the verification sheet")
    func start_verified_doesNotOpenVerification() {
        let onrampCoordinator = OnrampCoordinator(session: .verifiedMock, flipClient: .mock)
        onrampCoordinator.start(
            .launch(
                mint: .jeffy,
                displayName: "Test",
                launchAmount: .mockOne,
                launchFee: .mockOne
            ),
            amount: .mockOne
        )
        #expect(onrampCoordinator.isShowingVerificationFlow == false)
    }

    @Test("start with an unverified user opens the verification sheet")
    func start_unverified_opensVerification() {
        let onrampCoordinator = OnrampCoordinator(session: .unverifiedMock, flipClient: .mock)
        onrampCoordinator.start(
            .launch(
                mint: .jeffy,
                displayName: "Test",
                launchAmount: .mockOne,
                launchFee: .mockOne
            ),
            amount: .mockOne
        )
        #expect(onrampCoordinator.isShowingVerificationFlow == true)
    }

    @Test("applyDeeplinkVerification sets the confirm-email path and stashes the email")
    func applyDeeplinkVerification_setsConfirmEmailPath() {
        let onrampCoordinator = OnrampCoordinator(session: .unverifiedMock, flipClient: .mock)
        onrampCoordinator.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(onrampCoordinator.verificationPath == [.confirmEmailCode])
        #expect(onrampCoordinator.enteredEmail == "a@b.c")
    }
}
