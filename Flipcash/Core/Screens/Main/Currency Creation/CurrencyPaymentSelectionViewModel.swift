//
//  CurrencyPaymentSelectionViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@Observable
@MainActor
final class CurrencyPaymentSelectionViewModel {

    var dialogItem: DialogItem?
    /// The row the user confirmed paying with — its chevron becomes the
    /// in-flight loader while the launch preflights.
    private(set) var confirmedMint: PublicKey?

    @ObservationIgnored let launchCost: TokenAmount
    @ObservationIgnored private let displayRate: Rate?
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController

    /// - Parameter displayRate: Fixed display rate for flows anchored to a
    ///   single currency (the launch flow prices everything in USD); nil
    ///   follows the user's balance currency.
    init(launchCost: TokenAmount, displayRate: Rate? = nil, session: Session, ratesController: RatesController) {
        self.launchCost = launchCost
        self.displayRate = displayRate
        self.session = session
        self.ratesController = ratesController
    }

    /// Spendable payment sources; zero-value balances are hidden (nothing to pay with).
    var rows: [ExchangedBalance] {
        let rate = displayRate ?? ratesController.rateForBalanceCurrency()
        return session.balances(for: rate).filter { $0.exchangedFiat.hasDisplayableValue() }
    }

    /// Whether `row` alone can pay the launch cost — drives row enablement.
    func isEligible(_ row: ExchangedBalance) -> Bool {
        canPayLaunchCost(row.stored, launchCost: launchCost)
    }

    /// Raises the "Ready To Create?" confirmation; `onConfirm` runs only if the
    /// user taps "Pay To Create Currency". Ineligible rows never reach here.
    func select(_ row: ExchangedBalance, onConfirm: @escaping (StoredBalance) -> Void) {
        guard isEligible(row) else { return }
        dialogItem = .info(
            title: "Ready To Create?",
            subtitle: "You won't be able to change the name once your currency is created"
        ) {
            .standard("Pay To Create Currency") { [weak self] in
                self?.confirmedMint = row.stored.mint
                onConfirm(row.stored)
            };
            .dismiss(kind: .subtle)
        }
    }
}
