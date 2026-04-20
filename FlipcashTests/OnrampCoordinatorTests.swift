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
        let coordinator = OnrampCoordinator(session: .mock, flipClient: .mock)
        coordinator.cancel()
        #expect(coordinator.coinbaseOrder == nil)
        #expect(coordinator.verificationSheet == nil)
        #expect(coordinator.completion == nil)
    }

    @Test("startLaunch with a verified user does not open the verification sheet")
    func startLaunch_verified_doesNotOpenVerification() {
        let coordinator = OnrampCoordinator(session: .verifiedMock, flipClient: .mock)
        coordinator.startLaunch(
            amount: .mockOne,
            displayName: "Test",
            onCompleted: { _, _ in .launch(swapId: .generate(), mint: .jeffy) }
        )
        #expect(coordinator.isShowingVerificationFlow == false)
    }

    @Test("startLaunch with an unverified user opens the verification sheet")
    func startLaunch_unverified_opensVerification() {
        let coordinator = OnrampCoordinator(session: .unverifiedMock, flipClient: .mock)
        coordinator.startLaunch(
            amount: .mockOne,
            displayName: "Test",
            onCompleted: { _, _ in .launch(swapId: .generate(), mint: .jeffy) }
        )
        #expect(coordinator.isShowingVerificationFlow == true)
    }

    @Test("applyDeeplinkVerification sets the confirm-email path and stashes the email")
    func applyDeeplinkVerification_setsConfirmEmailPath() {
        let coordinator = OnrampCoordinator(session: .unverifiedMock, flipClient: .mock)
        coordinator.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(coordinator.verificationPath == [.confirmEmailCode])
        #expect(coordinator.enteredEmail == "a@b.c")
    }
}
