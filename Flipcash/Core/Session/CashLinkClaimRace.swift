//
//  CashLinkClaimRace.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import GRPCCore

/// Tells a claim that lost a race from a claim that failed.
///
/// When two users claim one cash link at once, the server's database commit fails for the loser
/// and the submit comes back as gRPC `INTERNAL` instead of `staleState(alreadyClaimed)`. Until the
/// server returns `STALE_STATE`, the gift card's own claim state is the only way to tell the two
/// apart.
nonisolated enum CashLinkClaimRace {

    /// Whether `error` from the claim submit means another claim won, as read from the gift card.
    ///
    /// Only `INTERNAL` is asked about. A failed re-read answers `false`, so the caller reports the
    /// original error rather than the lookup's.
    static func lostClaim(
        _ error: ErrorSubmitIntent,
        giftCard: KeyPair,
        requestingOwner: KeyPair,
        reader: some GiftCardAccountReading
    ) async -> Bool {
        guard case .grpcStatus(let status) = error, status.code == .internalError else {
            return false
        }
        let info = try? await reader.fetchAccountInfo(
            type: .giftCard,
            owner: giftCard,
            requestingOwner: requestingOwner
        )
        return info?.claimState == .claimed
    }
}
