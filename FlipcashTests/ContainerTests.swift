//
//  ContainerTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
struct ContainerTests {

    /// Canary for every `Container.isRunningUnitTests` guard — `Session` and
    /// `SessionContainer` skip their server-backed bootstrap under unit tests
    /// so test-built sessions don't fire doomed RPCs at production. If the
    /// test host stops setting `XCTestConfigurationFilePath`, those guards
    /// all silently disable; this fails loudly instead.
    @Test("unit test host is detected as a unit test run")
    func isRunningUnitTests_underTestHost_isTrue() {
        #expect(Container.isRunningUnitTests)
    }
}
