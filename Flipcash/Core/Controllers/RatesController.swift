//
//  RatesController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
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
    
    private var poller: Poller!
    
    // MARK: - Init -
    
    init(container: Container, database: Database) {
        self.client   = container.client
        self.database = database
        
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
        
        registerPoller()
    }
    
    // MARK: - Poller -
    
    private func registerPoller() {
        poller = Poller(seconds: 55, fireImmediately: true) { [weak self] in
            Task {
                try await self?.poll()
            }
        }
    }
    
    private func poll() async throws {
        try await fetchExchangeRates()
    }
    
    // MARK: - Rates -
    
    
    private func fetchExchangeRates() async throws {
        let snapshot = try await client.fetchExchangeRates()
        try database.insert(snapshot: snapshot)
    }
    
    func rateForBalanceCurrency() -> Rate {
        rate(for: balanceCurrency) ?? .oneToOne
    }
    
    func rateForEntryCurrency() -> Rate {
        rate(for: entryCurrency) ?? .oneToOne
    }
    
    func rate(for currency: CurrencyCode) -> Rate? {
        try? database.rate(for: currency)
    }
    
    func exchangedFiat(for amount: Quarks) throws -> ExchangedFiat {
        guard let rate = rate(for: amount.currencyCode) else {
            throw Error.exchangeRateUnavailable
        }
        
        let exchangedFiat = try ExchangedFiat(
            converted: amount,
            rate: rate,
            mint: .usdc
        )
        
        return exchangedFiat
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
    func getSelectedToken(default defaultMint: PublicKey = .usdc) -> StoredMintMetadata? {
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
