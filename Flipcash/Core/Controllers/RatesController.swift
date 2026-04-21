//
//  RatesController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import Combine
import FlipcashCore

private let logger = Logger(label: "flipcash.rates-controller")

/// Manages currency selection, exchange rates, and live mint data streaming.
///
/// Owns the ``VerifiedProtoService`` for exchange rate proofs and a
/// ``LiveMintDataStreamer`` for real-time rate updates. Currency preferences
/// are persisted to `UserDefaults` via `LocalDefaults`.
///
/// Inject via `@Environment(RatesController.self)`.
@MainActor @Observable
class RatesController {
    /// The currency used for amount entry (e.g. on the Give screen).
    /// Persisted to `UserDefaults` on change.
    var entryCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.entryCurrency = newValue
        }
    }

    /// The currency used for displaying balances.
    /// Persisted to `UserDefaults` on change.
    var balanceCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.balanceCurrency = newValue
        }
    }

    /// The currently selected token mint
    var selectedTokenMint: PublicKey? {
        didSet {
            if let mint = selectedTokenMint {
                LocalDefaults.storedTokenMint = mint.base58
            }
        }
    }

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let database: Database

    /// Service for verified exchange rate and reserve state proofs
    @ObservationIgnored let verifiedProtoService: VerifiedProtoService

    /// Streamer for live mint data
    @ObservationIgnored private var liveMintDataStreamer: LiveMintDataStreamer?

    /// Current set of mints being streamed.
    /// Always includes USDF — the server only delivers core mint fiat
    /// exchange rates when the core mint is in the subscription.
    @ObservationIgnored private(set) var streamedMints: Set<PublicKey> = [.usdf]

    /// Mints added via ``ensureMintSubscribed(_:)`` that may not yet
    /// appear in the user's balance list. Prevents balance refreshes
    /// from dropping pending subscriptions.
    @ObservationIgnored private var pendingMints: Set<PublicKey> = []

    /// Combine cancellables for rate streaming subscription
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    /// Serial queue for persisting rate updates off the main thread.
    /// The in-memory `cachedRates` mutation has to stay on main (it's
    /// `@Observable` and drives SwiftUI re-renders), but the SQLite
    /// write-through is pure I/O and belongs on a background queue.
    /// `internal` (not `private`) so tests can sync-wait on it via
    /// `@testable import Flipcash`.
    @ObservationIgnored let rateWriteQueue = DispatchQueue(
        label: "flipcash.rates-controller.db-writes",
        qos: .utility
    )

    // MARK: - Init -

    init(container: Container, database: Database) {
        self.client   = container.client
        self.database = database
        self.verifiedProtoService = VerifiedProtoService()

        if LocalDefaults.entryCurrency == nil {
            LocalDefaults.entryCurrency = .local() ?? .usd
        }

        if LocalDefaults.balanceCurrency == nil {
            LocalDefaults.balanceCurrency = .local() ?? .usd
        }

        entryCurrency   = LocalDefaults.entryCurrency!
        balanceCurrency = LocalDefaults.balanceCurrency!
        selectedTokenMint = loadSelectedToken()

        // Rehydrate last-known display rates from the database so screens
        // that read rateFor{Balance,Entry}Currency render in the user's
        // selected currency on cold launch instead of flashing USD while
        // waiting for the live mint stream to deliver its first batch.
        // The stream overwrites these within seconds. Display rates are
        // unsigned and have no validity window — intent submission still
        // goes through the verified-proof path (VerifiedProtoService),
        // which is intentionally untouched because those proofs carry
        // validity windows that would need a server-team conversation
        // before being persisted the same way.
        //
        // Runs synchronously on the main actor at init so the first
        // SwiftUI render already has warm data. The duration is logged
        // below as a regression guardrail — on a real device this is
        // expected to be a low single-digit millisecond cost for ~200
        // currencies. If it ever grows past ~20ms the read path should
        // be reshaped (bulk decode, column-typed storage, etc.) rather
        // than moved async, because async rehydration would bring the
        // USD flash back.
        let rehydrateStart = CFAbsoluteTimeGetCurrent()
        for rate in (try? database.getRates()) ?? [] {
            cachedRates[rate.currency] = rate
        }
        let rehydrateMs = (CFAbsoluteTimeGetCurrent() - rehydrateStart) * 1000
        logger.info("Rehydrated cached rates", metadata: [
            "count": "\(cachedRates.count)",
            "durationMs": "\(String(format: "%.2f", rehydrateMs))",
        ])

        // Create the streamer using the client factory method
        liveMintDataStreamer = client.createLiveMintDataStreamer(
            verifiedProtoService: verifiedProtoService
        )

        // Subscribe to rate updates from the verified proto service
        verifiedProtoService.ratesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rates in
                self?.updateRates(rates)
            }
            .store(in: &cancellables)

        // Subscribe to reserve state updates and persist live supply to database
        verifiedProtoService.reserveStatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updates in
                guard let self else { return }
                do {
                    try self.database.updateLiveSupply(updates: updates, date: .now)
                } catch {
                    logger.warning("Failed to update live supply", metadata: ["error": "\(error)"])
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Streaming Lifecycle -

    /// Start streaming live mint data for the specified mints.
    /// Called when user logs in or app becomes active.
    func startStreaming(mints: [PublicKey]) {
        streamedMints = Set(mints).union([.usdf])
        Task { await liveMintDataStreamer?.start(mints: streamedMints) }
    }

    /// Stop streaming live mint data.
    /// Called when user logs out or app goes to background.
    func stopStreaming() {
        Task { await liveMintDataStreamer?.stop() }
    }

    /// Ensure the stream is alive after returning from background.
    func ensureStreamConnected() {
        Task { await liveMintDataStreamer?.ensureConnected() }
    }

    /// Update the list of mints to stream.
    /// Called when user's balances change (new tokens acquired).
    /// Preserves any mints added via ``ensureMintSubscribed(_:)``
    /// that aren't yet reflected in the balance list.
    func updateSubscribedMints(_ mints: [PublicKey]) {
        let merged = Set(mints).union(pendingMints).union([.usdf])
        // Drop pending mints that are now covered by the balance list
        pendingMints.subtract(mints)
        streamedMints = merged
        Task { await liveMintDataStreamer?.updateMints(merged) }
    }

    // MARK: - Verified Proofs -

    /// Get verified state for intent construction.
    /// Returns nil if no verified exchange rate is available.
    func getVerifiedState(for currency: CurrencyCode, mint: PublicKey) async -> VerifiedState? {
        await verifiedProtoService.getVerifiedState(for: currency, mint: mint)
    }

    /// Ensure a mint is included in the live stream subscription.
    /// The verified state will arrive asynchronously through the existing
    /// streaming pipeline. No-op if the mint is already subscribed.
    /// Extra subscriptions are harmless — they reset on app restart.
    func ensureMintSubscribed(_ mint: PublicKey) {
        pendingMints.insert(mint)
        guard !streamedMints.contains(mint) else { return }
        streamedMints.insert(mint)
        Task { await liveMintDataStreamer?.updateMints(streamedMints) }
    }

    /// Wait for verified state to become available in the cache.
    /// Call ``ensureMintSubscribed(_:)`` first to trigger the stream.
    /// Polls the cache at short intervals, returning `nil` on timeout.
    ///
    /// For non-core mints (launchpad currencies), this method waits until
    /// `reserveProto` is also present — the server rejects intents without it.
    func awaitVerifiedState(
        for currency: CurrencyCode,
        mint: PublicKey,
        maxAttempts: Int = 25,
        interval: Duration = .milliseconds(200)
    ) async -> VerifiedState? {
        let requiresReserveState = mint != .usdf
        for i in 0..<maxAttempts {
            if Task.isCancelled { return nil }
            if i > 0 {
                try? await Task.sleep(for: interval)
            }
            
            logger.debug("Polling verified state", metadata: [
                "attempt": "\(i + 1)/\(maxAttempts)",
                "mint": "\(mint.base58)"
            ])
            
            if let state = await verifiedProtoService.getVerifiedState(for: currency, mint: mint) {
                if requiresReserveState && state.reserveProto == nil {
                    continue
                }
                return state
            }
        }
        logger.error("awaitVerifiedState timed out", metadata: ["currency": "\(currency.rawValue)", "mint": "\(mint.base58)"])
        return nil
    }

    // MARK: - Rates -

    /// Cache of rates from streaming. Tracked by `@Observable` so views update automatically.
    private(set) var cachedRates: [CurrencyCode: Rate] = [:]

    func rateForBalanceCurrency() -> Rate {
        rate(for: balanceCurrency) ?? .oneToOne
    }

    func rateForEntryCurrency() -> Rate {
        rate(for: entryCurrency) ?? .oneToOne
    }

    func rate(for currency: CurrencyCode) -> Rate? {
        cachedRates[currency]
    }

    func exchangedFiat(for amount: FiatAmount) throws -> ExchangedFiat {
        guard let rate = rate(for: amount.currency) else {
            throw Error.exchangeRateUnavailable
        }

        return ExchangedFiat(nativeAmount: amount, rate: rate)
    }

    /// Called when streaming delivers new rates. `VerifiedProtoService`
    /// has already deduped the batch against the last-known values, so
    /// everything in `rates` is a real delta that needs to be mirrored
    /// to the database. The in-memory mutation stays on main (drives
    /// SwiftUI via `@Observable`); the SQLite write runs on a
    /// background queue so it can't stall rendering.
    func updateRates(_ rates: [Rate]) {
        for rate in rates {
            cachedRates[rate.currency] = rate
        }

        // Capturing `database` across the queue boundary relies on
        // `Database: @unchecked Sendable`. If that conformance is ever
        // removed, this closure will fail to compile and the write path
        // needs to be reshaped (likely moving Database behind an actor).
        rateWriteQueue.async { [database] in
            do {
                try database.upsertRates(rates)
            } catch {
                logger.warning("Failed to persist rates", metadata: ["error": "\(error)"])
            }
        }
    }
    
    // MARK: - Token -
    private func loadSelectedToken() -> PublicKey? {
        guard let mintString = LocalDefaults.storedTokenMint,
              let mint = try? PublicKey(base58: mintString) else {
            return nil
        }
        
        return mint
    }
    
    /// Select a new mint and persist it
    /// - Parameter token: The token to save
    func selectToken(_ mint: PublicKey) {
        selectedTokenMint = mint
    }
    
    /// Get the currently selected token, or a default if none is selected
    /// - Parameter defaultMint: The default mint to return if none is selected. Defaults to USDC.
    /// - Returns: The selected token or the default
    func getSelectedToken(default defaultMint: PublicKey = .usdf) -> StoredMintMetadata? {
        let mint = selectedTokenMint ?? defaultMint
        
        return try? database.getMintMetadata(mint: mint)
    }
    
    /// Check if a given mint is currently selected
    /// - Parameter mint: The mint to check
    /// - Returns: True if the mint is selected
    func isSelectedToken(_ mint: PublicKey) -> Bool {
        selectedTokenMint == mint
    }
    
    /// Prepare for logout of current user
    func prepareForLogout() {
        selectedTokenMint = nil
        pendingMints.removeAll()
        stopStreaming()
        Task {
            await verifiedProtoService.clear()
        }
    }
}

// MARK: - Errors -

extension RatesController {
    enum Error: Swift.Error {
        case exchangeRateUnavailable
    }
}

// MARK: - LocalDefaults -

private enum LocalDefaults {
    @Defaults(.entryCurrency)
    static var entryCurrency: CurrencyCode?
    
    @Defaults(.balanceCurrency)
    static var balanceCurrency: CurrencyCode?

    @Defaults(.storedTokenMint)
    static var storedTokenMint: String?
}

extension RatesController {
    static let mock = RatesController(container: .mock, database: .mock)
}
