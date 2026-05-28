//
//  ContactResolver.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Resolves a contact's E.164 phone number to the recipient's payment
/// pubkey via the Flipcash resolver service. Wraps `FlipClient.resolvePhone`
/// with the signed-in owner so callers don't carry the keypair themselves.
///
/// Inject via `@Environment(ContactResolver.self)`. `@Observable` is required
/// by `@Environment` even though no fields are observable.
@Observable
final class ContactResolver {

    @ObservationIgnored nonisolated private let flipClient: FlipClient
    @ObservationIgnored nonisolated private let ownerKeyPair: KeyPair

    init(flipClient: FlipClient, ownerKeyPair: KeyPair) {
        self.flipClient   = flipClient
        self.ownerKeyPair = ownerKeyPair
    }

    nonisolated func resolveContact(e164: String) async throws -> PublicKey? {
        try await flipClient.resolvePhone(e164, owner: ownerKeyPair)
    }
}
