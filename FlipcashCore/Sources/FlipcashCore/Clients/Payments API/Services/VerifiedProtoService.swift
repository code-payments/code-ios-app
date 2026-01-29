//
//  VerifiedProtoService.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
@preconcurrency import Combine
import FlipcashAPI

/// Service that manages verified exchange rate and reserve state proofs received from streaming.
/// Used by TransactionService when constructing intents that require verified exchange data.
public actor VerifiedProtoService {

    /// Exchange rates keyed by currency code
    private var exchangeRates: [CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate] = [:]

    /// Reserve states keyed by mint address
    private var reserveStates: [PublicKey: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState] = [:]

    /// Publisher for rate updates. Emits array of Rate when rates are saved.
    public nonisolated let ratesPublisher = PassthroughSubject<[Rate], Never>()

    public init() {}

    // MARK: - Save Methods

    /// Save verified exchange rates from streaming batch.
    /// Publishes the parsed rates via `ratesPublisher` for observers.
    public func saveRates(_ rates: [Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate]) {
        var parsedRates: [Rate] = []

        for rate in rates {
            guard let currency = try? CurrencyCode(currencyCode: rate.exchangeRate.currencyCode) else {
                continue
            }
            exchangeRates[currency] = rate
            parsedRates.append(Rate(
                fx: Decimal(rate.exchangeRate.exchangeRate),
                currency: currency
            ))
        }

        trace(.receive, components: "Saved \(rates.count) verified exchange rates")

        if !parsedRates.isEmpty {
            ratesPublisher.send(parsedRates)
        }
    }

    /// Save verified reserve states from streaming batch
    public func saveReserveStates(_ states: [Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState]) {
        for state in states {
            guard let mint = try? PublicKey(state.reserveState.mint.value) else {
                continue
            }
            reserveStates[mint] = state
        }

        trace(.receive, components: "Saved \(states.count) verified reserve states")
    }

    // MARK: - Retrieve Methods

    /// Get verified state for intent construction.
    /// Returns nil if no verified exchange rate is available for the currency.
    ///
    /// - Parameters:
    ///   - currency: The currency code for the exchange rate
    ///   - mint: The mint address (used to look up reserve state for launchpad currencies)
    /// - Returns: VerifiedState with exchange rate proof and optional reserve state proof
    public func getVerifiedState(for currency: CurrencyCode, mint: PublicKey) -> VerifiedState? {
        guard let rateProto = exchangeRates[currency] else {
            trace(.warning, components: "No verified exchange rate for \(currency.rawValue)")
            return nil
        }

        // Reserve state is only available for launchpad currencies (not core mint)
        let reserveProto = reserveStates[mint]

        return VerifiedState(
            rateProto: rateProto,
            reserveProto: reserveProto
        )
    }

    /// Check if we have a verified exchange rate for a given currency
    public func hasVerifiedRate(for currency: CurrencyCode) -> Bool {
        exchangeRates[currency] != nil
    }

    /// Get the verified exchange rate proto directly (for display or debugging)
    public func getVerifiedRate(for currency: CurrencyCode) -> Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate? {
        exchangeRates[currency]
    }

    /// Get simple exchange rate for display purposes.
    /// Extracts the fx rate from the verified proto.
    public func rate(for currency: CurrencyCode) -> Rate? {
        guard let proto = exchangeRates[currency] else {
            return nil
        }
        return Rate(
            fx: Decimal(proto.exchangeRate.exchangeRate),
            currency: currency
        )
    }

    /// Get the verified reserve state proto directly (for display or debugging)
    public func getVerifiedReserveState(for mint: PublicKey) -> Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState? {
        reserveStates[mint]
    }

    /// Clear all stored proofs (called on logout)
    public func clear() {
        exchangeRates.removeAll()
        reserveStates.removeAll()
        trace(.note, components: "Cleared all verified proofs")
    }
}
