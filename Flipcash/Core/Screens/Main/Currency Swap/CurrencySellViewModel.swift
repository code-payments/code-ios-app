//
//  CurrencySellViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor @Observable
class CurrencySellViewModel: Identifiable {
    var enteredAmount: String = ""
    var path: [CurrencySellPath] = []
    var dialogItem: DialogItem?
    @ObservationIgnored let currencyMetadata: StoredMintMetadata

    var enteredFiat: ExchangedFiat? {
        computeAmount(using: ratesController.rateForEntryCurrency())
    }

    var canPerformAction: Bool {
        guard enteredFiat != nil else {
            return false
        }

        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount
        )
    }

    var screenTitle: String {
        return "Amount To Sell"
    }

    var maxPossibleAmount: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: currencyMetadata.mint),
            rate: entryRate,
            supplyQuarks: nil
        )

        guard let balance = session.balance(for: currencyMetadata.mint) else {
            return zero
        }

        return balance.computeExchangedValue(with: entryRate)
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController

    // MARK: - Init -

    init(currencyMetadata: StoredMintMetadata, session: Session, ratesController: RatesController) {
        self.currencyMetadata = currencyMetadata
        self.session = session
        self.ratesController = ratesController
    }

    // MARK: - Actions -

    func showConfirmationScreen() {
        guard enteredFiat != nil else { return }

        Task {
            guard let (amount, pin) = await prepareSubmission() else {
                dialogItem = .staleRate
                return
            }
            path.append(.confirmation(amount: amount, pinnedState: pin))
        }
    }

    /// Resolves the pin and computes the amount carried into the confirmation
    /// screen — confirmation and `Session.sell` receive the same pin.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        let currency = ratesController.entryCurrency
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: currencyMetadata.mint) else {
            return nil
        }
        guard let amount = computeAmount(using: pin.rate, pinnedSupplyQuarks: pin.supplyFromBonding) else {
            return nil
        }
        return (amount, pin)
    }

    /// Preview passes `nil` for `pinnedSupplyQuarks` (falls back to live metadata);
    /// submit passes the pinned supply so rate and supply come from one proof.
    private func computeAmount(using rate: Rate, pinnedSupplyQuarks: UInt64? = nil) -> ExchangedFiat? {
        guard !enteredAmount.isEmpty else { return nil }
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else { return nil }
        guard let supplyQuarks = pinnedSupplyQuarks ?? currencyMetadata.supplyFromBonding else { return nil }

        let balance = session.balance(for: currencyMetadata.mint)

        return ExchangedFiat.compute(
            fromEntered: FiatAmount(value: amount, currency: rate.currency),
            rate: rate,
            mint: currencyMetadata.mint,
            supplyQuarks: supplyQuarks,
            balance: balance.map(\.usdf),
            tokenBalanceQuarks: balance?.quarks
        )
    }

}

enum CurrencySellPath: Hashable {
    case confirmation(amount: ExchangedFiat, pinnedState: VerifiedState)
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
}
