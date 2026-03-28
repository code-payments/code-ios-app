//
//  StreamReferenceHealthTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("BidirectionalStreamReference Health")
struct StreamReferenceHealthTests {

    typealias Reference = BidirectionalStreamReference<String, String>

    // MARK: - hasRecentPing -

    @Test("No ping received returns not recent")
    func noPing() {
        let ref = Reference()
        #expect(ref.lastPing == nil)
        #expect(!ref.hasRecentPing)
    }

    @Test("Ping just received returns recent")
    func freshPing() {
        let ref = Reference()
        ref.receivedPing()
        #expect(ref.hasRecentPing)
    }

    @Test("Stale ping returns not recent")
    func stalePing() {
        let ref = Reference()
        ref.receivedPing()
        ref.lastPing = Date.now.addingTimeInterval(-20)
        #expect(!ref.hasRecentPing)
    }

    // MARK: - pingTimeout -

    @Test("Default ping timeout is 15 seconds")
    func defaultTimeout() {
        let ref = Reference()
        #expect(ref.pingTimeout == 15)
    }

    @Test("Ping timeout doubles server value")
    func doubledTimeout() {
        let ref = Reference()
        ref.receivedPing(updatedTimeout: 10)
        #expect(ref.pingTimeout == 20)
    }

    @Test("Ping timeout unchanged when server omits value")
    func timeoutPreserved() {
        let ref = Reference()
        ref.receivedPing(updatedTimeout: 5) // pingTimeout = 10
        ref.receivedPing()                  // no updatedTimeout
        #expect(ref.pingTimeout == 10)
    }

    // MARK: - isLikelyHealthy -

    @Test("Not healthy without stream even with recent ping")
    func notHealthyWithoutStream() throws {
        let ref = Reference()
        ref.receivedPing()
        try #require(ref.hasRecentPing)
        #expect(!ref.isLikelyHealthy)
    }
}
