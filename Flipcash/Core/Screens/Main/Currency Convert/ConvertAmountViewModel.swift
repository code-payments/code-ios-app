//
//  ConvertAmountViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.convert-amount")

/// Amount entry for converting `sourceBalance` into a chosen destination. The
/// amount is entered in the source's fiat value (like Sell); the pin is taken
/// against the source mint, and the same source amount feeds both the sell
/// (→ Dollars) and buy-with-currency (→ token) legs on the confirmation.
@Observable
@MainActor
final class ConvertAmountViewModel {
    var enteredAmount: String = ""
    var dialogItem: DialogItem?
    /// The chosen destination mint. Defaults to Dollars — unless we're
    /// converting *from* Dollars, where Dollars can't be the destination.
    var destinationMint: PublicKey

    @ObservationIgnored let sourceBalance: StoredBalance

    var screenTitle: String { "Convert" }

    /// The most the user can convert — this currency's spendable balance.
    var maxPossibleAmount: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: sourceBalance.mint),
            rate: rate,
            supplyQuarks: nil
        )

        guard let balance = session.balance(for: sourceBalance.mint) else {
            return zero
        }

        return balance.computeExchangedValue(with: rate)
    }

    /// Destinations offered in the picker: Dollars plus every other held
    /// balance, excluding the source. Read by the destination picker sheet.
    var destinationOptions: [ExchangedBalance] {
        let rate = ratesController.rateForBalanceCurrency()
        return session.balances(for: rate)
            .filter { $0.stored.mint != sourceBalance.mint }
    }

    /// Display name of the current destination — "Dollars" for USDF.
    var destinationName: String {
        session.balance(for: destinationMint)?.name ?? "Dollars"
    }

    /// Logo of the current destination, resolved from the held-balance cache.
    var destinationImageURL: URL? {
        session.balance(for: destinationMint)?.imageURL
    }

    var enteredFiat: ExchangedFiat? {
        computeAmount(using: ratesController.rateForBalanceCurrency())
    }

    var canPerformAction: Bool {
        guard enteredFiat != nil else { return false }

        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount
        )
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let amountValidator = AmountValidator()

    // MARK: - Init -

    init(sourceBalance: StoredBalance, session: Session, ratesController: RatesController) {
        self.sourceBalance = sourceBalance
        self.session = session
        self.ratesController = ratesController

        // Default to Dollars, except when converting *from* Dollars — then pick
        // the largest other holding so the destination is never the source.
        if sourceBalance.mint == .usdf {
            let rate = ratesController.rateForBalanceCurrency()
            let options = session.balances(for: rate).filter { $0.stored.mint != .usdf }
            self.destinationMint = options
                .max(by: { $0.exchangedFiat.nativeAmount.value < $1.exchangedFiat.nativeAmount.value })?
                .stored.mint ?? .usdf
        } else {
            self.destinationMint = .usdf
        }
    }

    // MARK: - Actions -

    func showConfirmation(router: AppRouter) {
        correctEntryToAffordable()
        guard enteredFiat != nil else { return }

        Task {
            guard let (amount, pin) = await prepareSubmission() else {
                dialogItem = .error(title: "Rate Unavailable", subtitle: "Couldn't get a fresh rate. Please try again.")
                return
            }
            router.pushAny(ConvertFlowPath.confirmation(
                sourceMint: sourceBalance.mint,
                destinationMint: destinationMint,
                destinationName: destinationName,
                amount: amount,
                sellFeeBps: sourceBalance.sellFeeBps,
                pinnedState: pin
            ))
        }
    }

    /// Drops the entry to the most the source balance can fund once the fee is
    /// applied, when the entry as typed would overrun it.
    ///
    /// Only converting *out of Dollars* can overrun: that leg charges its 1% on
    /// top of the entry, while a token source has the pool fee taken out of the
    /// sale, so the debit never exceeds what was entered. Amount entry is capped
    /// at the raw balance, so the overrun is at most the fee — small and bounded
    /// enough to correct silently rather than put to the user.
    func correctEntryToAffordable() {
        guard sourceBalance.mint == .usdf else { return }
        guard let entered = amountValidator.validate(enteredAmount) else { return }

        let balance = maxPossibleAmount.nativeAmount
        guard let corrected = entryAffordableAfterFee(
            entered: entered,
            balance: balance,
            feeBps: 100,
            feeChargedOnTop: true
        ) else { return }

        enteredAmount = amountValidator.string(
            from: corrected.value,
            fractionDigits: balance.currency.maximumFractionDigits
        )
    }

    /// Resolves the pin against the source mint and computes the source amount
    /// carried into the confirmation — confirmation and the swap receive the
    /// same pin.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        let currency = ratesController.balanceCurrency
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: sourceBalance.mint) else {
            logger.warning("No pinned state for source mint", metadata: [
                "sourceMint": "\(sourceBalance.mint.base58)",
                "currency": "\(currency.rawValue)",
            ])
            return nil
        }
        guard let amount = computeAmount(using: pin.rate, pinnedSupplyQuarks: pin.supplyFromBonding) else {
            return nil
        }
        return (amount, pin)
    }

    /// Preview passes `nil` for `pinnedSupplyQuarks` (falls back to live
    /// metadata); submit passes the pinned supply so rate and supply come from
    /// one proof.
    private func computeAmount(using rate: Rate, pinnedSupplyQuarks: UInt64? = nil) -> ExchangedFiat? {
        guard !enteredAmount.isEmpty else { return nil }
        guard let amount = amountValidator.validate(enteredAmount) else { return nil }

        let balance = session.balance(for: sourceBalance.mint)

        // USDF has no bonding curve — converting *from* Dollars is a buy paid
        // with reserves, so there's no supply to pin (supplyQuarks is unused).
        let supplyQuarks: UInt64
        if sourceBalance.mint == .usdf {
            supplyQuarks = 0
        } else {
            guard let supply = pinnedSupplyQuarks ?? sourceBalance.supplyFromBonding else { return nil }
            supplyQuarks = supply
        }

        return ExchangedFiat.compute(
            fromEntered: FiatAmount(value: amount, currency: rate.currency),
            rate: rate,
            mint: sourceBalance.mint,
            supplyQuarks: supplyQuarks,
            balance: balance.map(\.usdf),
            tokenBalanceQuarks: balance?.quarks
        )
    }
}
