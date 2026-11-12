//
//  UnitTestHostPollingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import Flipcash

/// Test sessions and authenticators are wired to real mainnet clients, so a
/// running poller sends live RPCs from the test host for the whole run.
@MainActor
@Suite("Unit-test host polling")
struct UnitTestHostPollingTests {

    @Test("A session built in the unit-test host doesn't poll")
    func session_doesNotPoll() {
        let session = Session.mock

        #expect(!session.isPolling)
    }

    @Test("An authenticator built in the unit-test host doesn't poll")
    func authenticator_doesNotPoll() {
        let authenticator = SessionAuthenticator(container: .mock)

        #expect(!authenticator.isPolling)
    }
}
