//
//  VerifiedState.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Bundles verified proofs for intent construction.
/// Contains server-signed exchange rate and optional reserve state for launchpad currencies.
public struct VerifiedState: Hashable, Sendable {

    /// Exchange rate proof (always required for payments)
    public let rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate

    /// Reserve state proof (only for launchpad currencies, nil for core mint)
    public let reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState?

    /// Server-signed timestamp for this proof bundle, computed at construction.
    /// When both protos are present, the older of the two drives staleness
    /// (closest to its server-side expiry). Cached as a stored property so
    /// `isStale` (called per SwiftUI body re-evaluation) doesn't walk the
    /// proto chain on every read.
    public let serverTimestamp: Date

    public init(
        rateProto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate,
        reserveProto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? = nil
    ) {
        self.rateProto = rateProto
        self.reserveProto = reserveProto
        let rateDate = rateProto.exchangeRate.timestamp.date
        if let reserveProto {
            self.serverTimestamp = min(rateDate, reserveProto.reserveState.timestamp.date)
        } else {
            self.serverTimestamp = rateDate
        }
    }

    /// Hashes a lightweight fingerprint rather than the full proto tree.
    /// `VerifiedState` is embedded in `CurrencySellPath.confirmation`, which
    /// `NavigationStack` hashes when diffing; the default synthesized
    /// `hash(into:)` would walk the proto signature bytes on every diff.
    /// Collisions are allowed by `Hashable` — `==` still compares the full
    /// struct.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(serverTimestamp)
        hasher.combine(rateProto.exchangeRate.exchangeRate)
        hasher.combine(reserveProto?.reserveState.supplyFromBonding)
    }
}

// MARK: - Convenience Accessors

extension VerifiedState {

    public var currencyCode: CurrencyCode? {
        try? CurrencyCode(currencyCode: rateProto.exchangeRate.currencyCode)
    }

    public var exchangeRate: Double {
        rateProto.exchangeRate.exchangeRate
    }

    /// `Rate` reconstructed from the signed proto. Pinned flows must compute
    /// `ExchangedFiat` against this — using the live `RatesController.cachedRates`
    /// instead lets stream updates drift the entered quarks away from what the
    /// server will validate against `rateProto`, producing
    /// "native amount and quark value mismatch".
    ///
    /// Non-optional because a `VerifiedState` can only originate from
    /// `VerifiedProtoService`, which keys its cache by an already-parsed
    /// `CurrencyCode`. If parsing ever fails here, the cache itself is
    /// corrupted and we want to crash loudly rather than silently submit
    /// against `.usd`.
    public var rate: Rate {
        guard let currency = currencyCode else {
            preconditionFailure("VerifiedState.rate: rateProto.currencyCode is unparseable; VerifiedProtoService cache integrity violated")
        }
        return Rate(fx: Decimal(exchangeRate), currency: currency)
    }

    public var timestamp: Date {
        rateProto.exchangeRate.timestamp.date
    }

    public var reserveTimestamp: Date? {
        reserveProto?.reserveState.timestamp.date
    }

    public var supplyFromBonding: UInt64? {
        reserveProto?.reserveState.supplyFromBonding
    }

    /// Client-side freshness ceiling. Server accepts proofs up to 15 minutes old;
    /// we stop at 13 to leave a 2-minute buffer for RTT and clock skew.
    public static let clientMaxAge: TimeInterval = 13 * 60

    public var age: TimeInterval {
        Date().timeIntervalSince(serverTimestamp)
    }

    public var isStale: Bool {
        age >= Self.clientMaxAge
    }
}
