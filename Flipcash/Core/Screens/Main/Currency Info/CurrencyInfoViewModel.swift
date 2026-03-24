//
//  CurrencyInfoViewModel.swift
//  Code
//
//  Created by Claude on 2025-02-04.
//

import SwiftUI
import FlipcashCore

@MainActor @Observable
class CurrencyInfoViewModel {

    enum LoadingState {
        case loading
        case loaded(StoredMintMetadata)
        case error(Error)
    }

    enum Error: Swift.Error {
        case mintNotFound
        case networkError
    }

    private(set) var loadingState: LoadingState = .loading

    @ObservationIgnored private var updateableMint: Updateable<StoredMintMetadata>?

    var mintMetadata: StoredMintMetadata? {
        switch loadingState {
        case .loaded(let metadata):
            return metadata
        case .loading, .error:
            return nil
        }
    }

    var isLoaded: Bool {
        if case .loaded = loadingState { return true }
        return false
    }

    @ObservationIgnored private let mint: PublicKey
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let database: Database
    @ObservationIgnored private let ratesController: RatesController

    // MARK: - Computed Properties -

    /// The current balance for this currency converted to the user's
    /// selected display currency. Returns zero quarks when metadata
    /// hasn't loaded or the user holds no balance for this mint.
    var balance: Quarks {
        let rate = ratesController.rateForBalanceCurrency()
        let zero = Quarks.zero(currencyCode: rate.currency, decimals: PublicKey.usdf.mintDecimals)

        guard let mintMetadata else { return zero }
        guard let stored = session.balance(for: mintMetadata.mint) else { return zero }

        let exchanged = try? ExchangedFiat(underlying: stored.usdf, rate: rate, mint: .usdf)
        return exchanged?.converted ?? zero
    }

    /// The user's USDF reserve balance converted to the display currency.
    /// Returns `nil` when the user has no USDF balance.
    var reserveBalance: ExchangedFiat? {
        guard let stored = session.balance(for: .usdf) else { return nil }

        let rate = ratesController.rateForBalanceCurrency()
        return try? ExchangedFiat(underlying: stored.usdf, rate: rate, mint: .usdf)
    }

    /// The absolute appreciation (or depreciation) of this currency's balance
    /// relative to its cost basis, converted to the display currency.
    /// Returns zero with `isPositive: true` when
    /// metadata or balance is unavailable.
    var appreciation: (amount: Quarks, isPositive: Bool) {
        let rate = ratesController.rateForBalanceCurrency()
        let zero = Quarks.zero(currencyCode: rate.currency, decimals: PublicKey.usdf.mintDecimals)

        guard let mintMetadata, let balance = session.balance(for: mintMetadata.mint) else {
            return (zero, true)
        }
        let (appreciationValue, isPositive) = balance.computeAppreciation(with: rate)
        return (appreciationValue.converted, isPositive)
    }

    /// The market capitalisation of this currency (supply × spot price on the
    /// bonding curve), converted to the user's display currency. Returns zero
    /// when metadata is missing or the supply exceeds the curve's max.
    var marketCap: Quarks {
        guard let mintMetadata else { return 0 }

        let supply = Int(mintMetadata.supplyFromBonding ?? 0)

        let curve = DiscreteBondingCurve()
        guard let mCap = curve.marketCap(for: supply) else {
            return 0
        }

        let usdc = try! Quarks(
            fiatDecimal: mCap,
            currencyCode: .usd,
            decimals: mintMetadata.mint.mintDecimals
        )

        let exchanged = try! ExchangedFiat(
            underlying: usdc,
            rate: ratesController.rateForBalanceCurrency(),
            mint: .usdf
        )

        return exchanged.converted
    }

    // MARK: - Init -

    /// Initializes with a mint address. Attempts a fast database lookup;
    /// falls back to loading state until ``loadMintMetadata()`` completes.
    init(mint: PublicKey, session: Session, database: Database, ratesController: RatesController) {
        self.mint = mint
        self.session = session
        self.database = database
        self.ratesController = ratesController

        // Load from database immediately if available (fast path)
        if let cachedMetadata = try? database.getMintMetadata(mint: mint) {
            setupUpdateable(with: cachedMetadata)
            loadingState = .loaded(cachedMetadata)
        }
    }

    /// Initializes with pre-fetched metadata for instant display. Converts
    /// the ``MintMetadata`` to ``StoredMintMetadata`` and starts in the
    /// `.loaded` state — no loading spinner is shown.
    init(metadata: MintMetadata, session: Session, database: Database, ratesController: RatesController) {
        self.mint = metadata.address
        self.session = session
        self.database = database
        self.ratesController = ratesController

        let stored = StoredMintMetadata(metadata)
        setupUpdateable(with: stored)
        loadingState = .loaded(stored)
    }

    func loadMintMetadata() async {
        // If already loaded from cache, no need to show loading state
        let wasAlreadyLoaded = isLoaded

        do {
            let metadata = try await session.fetchMintMetadata(mint: mint)
            setupUpdateable(with: metadata)
            loadingState = .loaded(metadata)
        } catch Session.Error.mintNotFound {
            // Only show error if we didn't have cached data
            if !wasAlreadyLoaded {
                loadingState = .error(.mintNotFound)
            }
        } catch {
            // Only show error if we didn't have cached data
            if !wasAlreadyLoaded {
                loadingState = .error(.networkError)
            }
        }
    }

    private func setupUpdateable(with initialValue: StoredMintMetadata) {
        updateableMint = Updateable { [database, mint] in
            (try? database.getMintMetadata(mint: mint)) ?? initialValue
        } didSet: { [weak self] in
            guard let self, let updateable = self.updateableMint else { return }
            self.loadingState = .loaded(updateable.value)
        }
    }
}
