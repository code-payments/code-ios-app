//
//  ReceiptSettleGateTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import Flipcash

@MainActor
@Suite("ReceiptSettleGate")
struct ReceiptSettleGateTests {

    @Test("Holding sets the settling id")
    func holdSetsID() {
        let gate = ReceiptSettleGate(delay: .seconds(60))
        gate.hold("a")
        #expect(gate.settlingID == "a")
    }

    @Test("A newer hold replaces the current one")
    func newerHoldReplaces() {
        let gate = ReceiptSettleGate(delay: .seconds(60))
        gate.hold("a")
        gate.hold("b")
        #expect(gate.settlingID == "b")
    }

    @Test("Cancel clears the held id immediately")
    func cancelClears() {
        let gate = ReceiptSettleGate(delay: .seconds(60))
        gate.hold("a")
        gate.cancel()
        #expect(gate.settlingID == nil)
    }

    @Test("The held id clears on its own after the delay")
    func clearsAfterDelay() async throws {
        let gate = ReceiptSettleGate(delay: .milliseconds(20))
        gate.hold("a")
        #expect(gate.settlingID == "a")
        try await Task.sleep(for: .milliseconds(120))
        #expect(gate.settlingID == nil)
    }
}
