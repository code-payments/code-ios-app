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

        let exchanged = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: stored.usdf.quarks, mint: .usdf),
            rate: rate,
            supplyQuarks: nil
        )
        return (try? Quarks(
            fiatDecimal: exchanged.nativeAmount.value,
            currencyCode: exchanged.nativeAmount.currency,
            decimals: exchanged.nativeAmount.currency.maximumFractionDigits
        )) ?? zero
    }

    /// The user's USDF reserve balance converted to the display currency.
    /// Returns `nil` when the user has no USDF balance.
    var reserveBalance: ExchangedFiat? {
        guard let stored = session.balance(for: .usdf) else { return nil }

        let rate = ratesController.rateForBalanceCurrency()
        return ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: stored.usdf.quarks, mint: .usdf),
            rate: rate,
            supplyQuarks: nil
        )
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
        let appreciationAsQuarks = (try? Quarks(
            fiatDecimal: appreciationValue.nativeAmount.value,
            currencyCode: appreciationValue.nativeAmount.currency,
            decimals: appreciationValue.nativeAmount.currency.maximumFractionDigits
        )) ?? zero
        return (appreciationAsQuarks, isPositive)
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

        // `mCap` is a USD decimal. Build a USDF TokenAmount so the on-chain
        // and USDF sides agree at 6 decimals; using `mintMetadata.mint.mintDecimals`
        // here would scale a USDF value at the bonded mint's 10 decimals and
        // overshoot by 10⁴.
        let exchanged = ExchangedFiat.compute(
            onChainAmount: TokenAmount(wholeTokens: mCap, mint: .usdf),
            rate: ratesController.rateForBalanceCurrency(),
            supplyQuarks: nil
        )

        return (try? Quarks(
            fiatDecimal: exchanged.nativeAmount.value,
            currencyCode: exchanged.nativeAmount.currency,
            decimals: exchanged.nativeAmount.currency.maximumFractionDigits
        )) ?? 0
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
            // Skip redundant updates — @Observable fires on every set,
            // even with the same value, which would re-evaluate every
            // view observing loadingState on each poll cycle.
            if case .loaded(let current) = self.loadingState, current == updateable.value {
                return
            }
            self.loadingState = .loaded(updateable.value)
        }
    }
}
