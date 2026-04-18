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
}
