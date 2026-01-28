//
//  RatesController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import Combine
import FlipcashCore

@MainActor
class RatesController: ObservableObject {
    @Published var entryCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.entryCurrency = newValue
        }
    }

    @Published var balanceCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.balanceCurrency = newValue
        }
    }

    @Published var onrampCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.onrampCurrency = newValue
        }
    }

    /// The currently selected token mint
    @Published var selectedTokenMint: PublicKey? {
        didSet {
            if let mint = selectedTokenMint {
                LocalDefaults.storedTokenMint = mint.base58
            }
        }
    }

    private let client: Client
    private let database: Database

    /// Service for verified exchange rate and reserve state proofs
    let verifiedProtoService: VerifiedProtoService

    /// Streamer for live mint data
    private var liveMintDataStreamer: LiveMintDataStreamer?

    /// Current list of mints being streamed
    private var streamedMints: [PublicKey] = []

    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()

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
    }

    // MARK: - Streaming Lifecycle -

    /// Start streaming live mint data for the specified mints.
    /// Called when user logs in or app becomes active.
    func startStreaming(mints: [PublicKey]) {
        streamedMints = mints
        liveMintDataStreamer?.start(mints: mints)
    }

    /// Stop streaming live mint data.
    /// Called when user logs out or app goes to background.
    func stopStreaming() {
        liveMintDataStreamer?.stop()
    }

    /// Update the list of mints to stream.
    /// Called when user's balances change (new tokens acquired).
    func updateSubscribedMints(_ mints: [PublicKey]) {
        streamedMints = mints
        liveMintDataStreamer?.updateMints(mints)
    }

    // MARK: - Verified Proofs -

    /// Get verified state for intent construction.
    /// Returns nil if no verified exchange rate is available.
    func getVerifiedState(for currency: CurrencyCode, mint: PublicKey) async -> VerifiedState? {
        await verifiedProtoService.getVerifiedState(for: currency, mint: mint)
    }

    // MARK: - Rates -

    /// Cache of rates from streaming. Published so views update automatically.
    @Published private(set) var cachedRates: [CurrencyCode: Rate] = [:]

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
        
        return try! database.getMintMetadata(mint: mint)
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
