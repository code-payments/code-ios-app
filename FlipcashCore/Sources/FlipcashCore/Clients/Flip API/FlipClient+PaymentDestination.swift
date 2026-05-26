//
//  FlipClient+PaymentDestination.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Resolve a contact's E.164 phone to the Flipcash payment destination.
    /// Returns `nil` for NOT_FOUND (not registered with Flipcash); throws for
    /// hard failures.
    public func resolvePaymentDestination(phone: String, owner: KeyPair) async throws -> PublicKey? {
        try await withCheckedThrowingContinuation { c in
            paymentDestinationService.resolve(phone: phone, owner: owner) { c.resume(with: $0) }
        }
    }
}
