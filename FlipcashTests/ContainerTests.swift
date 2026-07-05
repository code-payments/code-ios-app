//
//  ContainerTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
struct ContainerTests {

    /// The root guarantee that test- and preview-built object graphs can never
    /// reach a real backend: every shared client mock resolves every host to
    /// loopback. Covers all three offline entry points independently —
    /// `Container.mock` (used by session/view-model tests) builds its own
    /// clients, while `Client.mock` / `FlipClient.mock` are separate instances
    /// used directly (e.g. the streamer stress tests). If any one is reverted
    /// to `.mainNet`, this fails loudly instead of silently resuming production
    /// traffic.
    @Test("every shared client mock is offline")
    func sharedClientMocks_areOffline() {
        #expect(Container.mock.flipClient.network == .offline)
        #expect(Container.mock.client.network == .offline)
        #expect(FlipClient.mock.network == .offline)
        #expect(Client.mock.network == .offline)
    }

    /// Canary for every `Container.isRunningUnitTests` guard — `Session` and
    /// `SessionContainer` skip their server-backed bootstrap under unit tests
    /// so test-built sessions don't do doomed work. If the test host stops
    /// setting `XCTestConfigurationFilePath`, those guards all silently
    /// disable; this fails loudly instead.
    @Test("unit test host is detected as a unit test run")
    func isRunningUnitTests_underTestHost_isTrue() {
        #expect(Container.isRunningUnitTests)
    }
}
