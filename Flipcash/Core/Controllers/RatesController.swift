//
//  RatesController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import Combine
import FlipcashCore

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

    /// The currency used for onramp (buy) flows.
    /// Persisted to `UserDefaults` on change.
    var onrampCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.onrampCurrency = newValue
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

    /// Current list of mints being streamed
    @ObservationIgnored private var streamedMints: [PublicKey] = []

    /// Mints added via ``ensureMintSubscribed(_:)`` that may not yet
    /// appear in the user's balance list. Prevents balance refreshes
    /// from dropping pending subscriptions.
    @ObservationIgnored private var pendingMints: Set<PublicKey> = []

    /// Combine cancellables for rate streaming subscription
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

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

        if LocalDefaults.onrampCurrency == nil {
            LocalDefaults.onrampCurrency = .usd
        }


        entryCurrency   = LocalDefaults.entryCurrency!
        balanceCurrency = LocalDefaults.balanceCurrency!
        onrampCurrency  = LocalDefaults.onrampCurrency!
        selectedTokenMint = loadSelectedToken()

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
                    trace(.warning, components: "Failed to update live supply: \(error)")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Streaming Lifecycle -

    /// Start streaming live mint data for the specified mints.
    /// Called when user logs in or app becomes active.
    func startStreaming(mints: [PublicKey]) {
        streamedMints = mints
        Task { await liveMintDataStreamer?.start(mints: mints) }
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
        var merged = mints
        for mint in pendingMints where !merged.contains(mint) {
            merged.append(mint)
        }
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
        updateSubscribedMints(streamedMints)
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
            if let state = await verifiedProtoService.getVerifiedState(for: currency, mint: mint) {
                if requiresReserveState && state.reserveProto == nil {
                    continue
                }
                return state
            }
        }
        trace(.failure, components: "awaitVerifiedState timed out for \(currency.rawValue), mint: \(mint.base58)")
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

    func exchangedFiat(for amount: Quarks) throws -> ExchangedFiat {
        guard let rate = rate(for: amount.currencyCode) else {
            throw Error.exchangeRateUnavailable
        }

        let exchangedFiat = try ExchangedFiat(
            converted: amount,
            rate: rate,
            mint: .usdf
        )

        return exchangedFiat
    }

    /// Called when streaming receives new rates. Updates the cache.
    func updateRates(_ rates: [Rate]) {
        for rate in rates {
            cachedRates[rate.currency] = rate
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
    
    @Defaults(.onrampCurrency)
    static var onrampCurrency: CurrencyCode?
    
    @Defaults(.storedTokenMint)
    static var storedTokenMint: String?
}

extension RatesController {
    static let mock = RatesController(container: .mock, database: .mock)
}
