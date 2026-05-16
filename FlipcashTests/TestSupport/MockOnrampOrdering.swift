//
//  MockOnrampOrdering.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

/// Test fake for `OnrampOrdering`. Records each `createOrder` call and lets
/// the test substitute a custom handler (return a fixture or throw).
///
/// `@MainActor`-isolated to satisfy the protocol's `Sendable` requirement
/// without needing `@unchecked` — matches the pattern used by
/// `MockTransactionSigning`. Tests drive the mock from the main actor.
@MainActor
final class MockOnrampOrdering: OnrampOrdering {

    private(set) var createOrderCalls: [OnrampOrderRequest] = []
    var createOrderHandler: ((OnrampOrderRequest) async throws -> OnrampOrderResponse)?

    func createOrder(
        request: OnrampOrderRequest,
        idempotencyKey: UUID?
    ) async throws -> OnrampOrderResponse {
        createOrderCalls.append(request)
        guard let handler = createOrderHandler else {
            return .fixture()
        }
        return try await handler(request)
    }
}
