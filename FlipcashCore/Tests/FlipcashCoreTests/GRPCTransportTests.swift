//
//  GRPCTransportTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("GRPCTransport — production transport construction")
struct GRPCTransportTests {

    /// `Container` constructs `Client`/`FlipClient` with `try!` on the grounds
    /// that transport construction cannot throw for our fixed DNS + TLS config
    /// (the only throwing path is a resolver-registry miss, and `.dns` targets
    /// have a built-in resolver). This test turns that comment into an
    /// executable guarantee: if a dependency bump ever changes the default
    /// resolver registry, CI fails here instead of the app crashing at launch.
    @Test("Transport construction does not throw for any production host", arguments: [
        Network.mainNet.hostForPayments,
        Network.mainNet.hostForCore,
    ])
    func makeTransportServicesDoesNotThrow(host: String) {
        #expect(throws: Never.self) {
            _ = try GRPCTransport.makeTransportServices(host: host, port: Network.mainNet.port)
        }
    }
}
