//
//  VerifiedStateResolution.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Outcome of a verified-state resolution attempt.
///
/// Encoded as an enum rather than `(VerifiedState?, source: Source)` so the
/// "state is nil iff cacheMiss" invariant holds at the type level — callers
/// can't accidentally consume `.cacheMiss` as if it had a value.
enum VerifiedStateResolution: Equatable, Sendable {
    case provided(VerifiedState)
    case cacheHit(VerifiedState)
    case cacheMiss

    /// Stable identifier suitable for log metadata.
    var sourceLabel: String {
        switch self {
        case .provided: return "provided"
        case .cacheHit: return "cache-hit"
        case .cacheMiss: return "cache-miss"
        }
    }

    var state: VerifiedState? {
        switch self {
        case .provided(let state), .cacheHit(let state):
            return state
        case .cacheMiss:
            return nil
        }
    }
}

/// Resolve a `VerifiedState`, preferring `provided` and falling back to
/// `cacheLookup`. Returns `.cacheMiss` when neither yields a proof.
func resolveVerifiedState(
    provided: VerifiedState?,
    currency: CurrencyCode,
    mint: PublicKey,
    cacheLookup: (CurrencyCode, PublicKey) async -> VerifiedState?
) async -> VerifiedStateResolution {
    if let provided {
        return .provided(provided)
    }
    if let cached = await cacheLookup(currency, mint) {
        return .cacheHit(cached)
    }
    return .cacheMiss
}
