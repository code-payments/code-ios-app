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

private let logger = Logger(label: "flipcash.verified-proto-service")

/// Lightweight value emitted when reserve states are saved from streaming.
public struct ReserveStateUpdate: Sendable {
    public let mint: PublicKey
    public let supplyFromBonding: UInt64

    public init(mint: PublicKey, supplyFromBonding: UInt64) {
        self.mint = mint
        self.supplyFromBonding = supplyFromBonding
    }
}

/// Service that manages verified exchange rate and reserve state proofs received from streaming.
/// Used by TransactionService when constructing intents that require verified exchange data.
public actor VerifiedProtoService {

    /// Exchange rates keyed by currency code
    private var exchangeRates: [CurrencyCode: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate] = [:]

    /// Reserve states keyed by mint address
    private var reserveStates: [PublicKey: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState] = [:]

    /// Publisher for rate updates. Emits array of Rate when rates are saved.
    public nonisolated let ratesPublisher = PassthroughSubject<[Rate], Never>()

    /// Publisher for reserve state updates. Emits parsed mint/supply pairs when reserve states are saved.
    public nonisolated let reserveStatesPublisher = PassthroughSubject<[ReserveStateUpdate], Never>()

    private let store: VerifiedProtoStore
    private let clock: @Sendable () -> Date

    public init(
        store: VerifiedProtoStore,
        clock: @Sendable @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.clock = clock
        Task { await self.warmLoadFromStore() }
    }

    private func warmLoadFromStore() async {
        do {
            for row in try store.allRates() {
                guard let currency = try? CurrencyCode(currencyCode: row.currency) else { continue }
                if let proto = try? Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate(serializedBytes: row.rateProto) {
                    exchangeRates[currency] = proto
                }
            }
            for row in try store.allReserves() {
                guard let key = try? PublicKey(base58: row.mint) else { continue }
                if let proto = try? Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState(serializedBytes: row.reserveProto) {
                    reserveStates[key] = proto
                }
            }
        } catch {
            logger.warning("Failed to warm-load verified protos", metadata: ["error": "\(error)"])
        }
    }

    // MARK: - Save Methods

    /// Save verified exchange rates from streaming batch.
    /// Only publishes updates for currencies whose `fx` actually changed,
    /// avoiding no-op downstream work (SwiftUI re-renders, DB writes).
    /// The full proto is still stored on every call so intent submission
    /// always uses the freshest signed rate proof, even when the
    /// numeric exchange rate is unchanged.
    public func saveRates(_ rates: [Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate]) {
        let now = clock()
        var parsedRates: [Rate] = []
        var unknownCodes: [String] = []

        for rate in rates {
            guard let currency = try? CurrencyCode(currencyCode: rate.exchangeRate.currencyCode) else {
                unknownCodes.append(rate.exchangeRate.currencyCode)
                continue
            }
            let fxChanged = exchangeRates[currency]?.exchangeRate.exchangeRate != rate.exchangeRate.exchangeRate
            exchangeRates[currency] = rate
            persistRate(currency: currency, proto: rate, receivedAt: now)
            if fxChanged {
                parsedRates.append(Rate(
                    fx: Decimal(rate.exchangeRate.exchangeRate),
                    currency: currency
                ))
            }
        }

        if !unknownCodes.isEmpty {
            logger.warning("Skipped exchange rates with unknown codes", metadata: [
                "skipped": "\(unknownCodes.count)",
                "total": "\(rates.count)",
                "codes": "\(unknownCodes.joined(separator: ","))"
            ])
        }

        if !parsedRates.isEmpty {
            logger.info("Exchange rates changed", metadata: [
                "changed": "\(parsedRates.count)",
                "total": "\(rates.count)",
            ])
            ratesPublisher.send(parsedRates)
        }
    }

    private func persistRate(
        currency: CurrencyCode,
        proto: Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate,
        receivedAt: Date
    ) {
        do {
            let data = try proto.serializedData()
            try store.writeRate(StoredRateRow(currency: currency.rawValue, rateProto: data, receivedAt: receivedAt))
        } catch {
            logger.warning("Failed to persist verified rate", metadata: [
                "currency": "\(currency.rawValue)",
                "error": "\(error)"
            ])
        }
    }

    /// Save verified reserve states from streaming batch.
    /// Only publishes updates for mints whose supply actually changed,
    /// avoiding no-op DB writes and cascading UI refreshes.
    public func saveReserveStates(_ states: [Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState]) {
        let now = clock()
        var updates: [ReserveStateUpdate] = []
        for state in states {
            guard let mint = try? PublicKey(state.reserveState.mint.value) else {
                continue
            }
            let supplyChanged = reserveStates[mint]?.reserveState.supplyFromBonding != state.reserveState.supplyFromBonding
            reserveStates[mint] = state
            persistReserve(mint: mint, proto: state, receivedAt: now)
            if supplyChanged {
                updates.append(ReserveStateUpdate(
                    mint: mint,
                    supplyFromBonding: state.reserveState.supplyFromBonding
                ))
            }
        }

        if !updates.isEmpty {
            reserveStatesPublisher.send(updates)
        }
    }

    private func persistReserve(
        mint: PublicKey,
        proto: Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState,
        receivedAt: Date
    ) {
        do {
            let data = try proto.serializedData()
            try store.writeReserve(StoredReserveRow(mint: mint.base58, reserveProto: data, receivedAt: receivedAt))
        } catch {
            logger.warning("Failed to persist verified reserve", metadata: [
                "mint": "\(mint.base58)",
                "error": "\(error)"
            ])
        }
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
            logger.warning("No verified exchange rate for currency", metadata: ["currency": "\(currency.rawValue)"])
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
        logger.debug("Cleared all verified proofs")
    }
}
