//
//  IntentLogID.swift
//  FlipcashCore
//

import Foundation

/// How an intent ID appears in logs: in full, or masked to its last six base58 characters while it is still usable.
struct IntentLogID: Sendable, Equatable {

    /// Characters of the base58 ID kept when masked.
    static let suffixLength = 6

    let id: PublicKey

    /// Whether anyone who reads the ID before it settles could spend it, as with a payment request's `payment_intent_id`.
    let isSensitive: Bool

    /// The ID to log before the intent settles or after it fails.
    var pending: String {
        isSensitive ? "…" + String(id.base58.suffix(Self.suffixLength)) : id.base58
    }

    /// The ID to log once the intent has succeeded.
    var settled: String {
        id.base58
    }
}
