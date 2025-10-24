//
//  GiveViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-10-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class GiveViewModel: ObservableObject {
    
    @Published var enteredAmount: String = ""
    @Published var actionState: ButtonState = .normal
    @Published var navigationPath: [GivePath] = []
    
    @Published var dialogItem: DialogItem?
    
    var canGive: Bool {
        enteredFiat != nil && (enteredFiat?.usdc.quarks ?? 0) > 0
    }
    
    let container: Container
    let sessionContainer: SessionContainer
    let session: Session
    let ratesController: RatesController
    let onrampViewModel: OnrampViewModel
    
    private(set) var selectedBalance: ExchangedBalance?
    
    private var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let selectedBalance else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount), amount > 0 else {
//            trace(.failure, components: "[Give] Failed to parse amount string: \(enteredAmount)")
            return nil
        }
        
        let currency = ratesController.entryCurrency
        let mint = selectedBalance.stored.mint
        
        guard let rate = ratesController.rate(for: currency) else {
            trace(.failure, components: "[Give] Rate not found for: \(currency)")
            return nil
        }
        
        let valuation: BondingCurve.Valuation

        if mint != PublicKey.usdc {
            guard let currentSupply = selectedBalance.stored.supplyFromBonding else {
                return nil
            }
            
            let curve = BondingCurve()
            valuation = try! curve.tokensForValueExchange(
                fiatDecimal: amount,
                fx: rate.fx,
                supplyQuarks: Int(currentSupply)
            )
        } else {
            valuation = .init(
                tokens: amount,
                fx: rate.fx
            )
        }
        
        // The rate for the underlying token
        // represented as the 'region' of Rate
        // so in the below example - CAD
        let underlyingRate = Rate(
            fx: valuation.fx,
            currency: rate.currency
        )
        
        // This a new fx rate for the token valued in USDC
        // so if the spot price for a token is $0.01 this
        // is an example of CAD -> Tokens:
        // - $5.00 CAD
        // - Rate: 1.40
        // - $3.57 USD
        // - 3.57 / 0.01 = # of tokens
        
        let exchanged: ExchangedFiat
        if currency == .usd {
            // Initializing exchangedFiat with usdc: will
            // mean that `converted` will always be off for
            // USDC as it will use the bonding curve rate
            // becase the server is expecting a non-1 fx
            let underlying = try! Fiat(
                fiatDecimal: amount,
                currencyCode: underlyingRate.currency,
                decimals: mint.mintDecimals
            )
            
            exchanged = try! ExchangedFiat(
                converted: underlying,
                rate: underlyingRate,
                mint: mint
            )
        } else {
            exchanged = try! ExchangedFiat(
                converted: .init(
                    fiatDecimal: amount,
                    currencyCode: underlyingRate.currency,
                    decimals: mint.mintDecimals
                ),
                rate: underlyingRate,
                mint: mint
            )
        }
        
        return  exchanged
    }
    
    private let isPresented: Binding<Bool>
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self.isPresented      = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.ratesController  = sessionContainer.ratesController
        self.onrampViewModel  = sessionContainer.onrampViewModel
    }
    
    // MARK: - Validation -
    
    private func hasSufficientFunds(for exchangedFiat: ExchangedFiat) -> (Bool, ExchangedFiat?) {        
        guard exchangedFiat.usdc.quarks > 0 else {
            return (false, nil)
        }
        
        let aggregate = AggregateBalance(
            entryRate: ratesController.rateForEntryCurrency(),
            balanceRate: ratesController.rateForBalanceCurrency(),
            balances: session.balances
        )
        
        let balance = aggregate.entryBalance(for: exchangedFiat.mint)
        
        guard let (available, amountToSend, _) = try? balance?.converted.aligned(with: exchangedFiat.converted) else {
            return (false, nil)
        }
        
        if amountToSend.quarks <= available.quarks {
            return (true, nil)
        } else {
            let delta = try! ExchangedFiat(
                converted: amountToSend.subtracting(available),
                rate: exchangedFiat.rate,
                mint: .usdc
            )
            return (false, delta)
        }
    }
    
    // MARK: - Action -
    
    func giveAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        let (hasSufficientFunds, delta) = hasSufficientFunds(for: exchangedFiat)
        
        guard hasSufficientFunds else {
            if let delta {
                showYoureShortError(amount: delta)
            } else {
                showInsufficientBalanceError()
            }
            return
        }
        
        guard session.hasLimitToSendFunds(for: exchangedFiat) else {
            showLimitsError()
            return
        }
        
        isPresented.wrappedValue = false
        
        Task {
            try await Task.delay(milliseconds: 50)
            
            session.showCashBill(
                .init(
                    kind: .cash,
                    exchangedFiat: exchangedFiat,
                    received: false
                )
            )
        }
    }
    
    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        enteredAmount = ""
        navigationPath.append(.giveScreen)
    }
    
    // MARK: - Navigation -
    
    private func presentOnramp() {
        onrampViewModel.presentRoot()
        Analytics.onrampOpenedFromGive()
    }
    
    // MARK: - Errors -
    
    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentOnramp()
            };
            .dismiss(kind: .subtle)
        }
    }
    
    private func showYoureShortError(amount: ExchangedFiat) {
        dialogItem = .init(
            style: .destructive,
            title: "You're \(amount.converted.formatted(suffix: nil)) Short",
            subtitle: "Add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentOnramp()
            };
            .dismiss(kind: .subtle)
        }
    }
    
    private func showLimitsError() {
        dialogItem = .init(
            style: .destructive,
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

enum GivePath: Hashable {
    case giveScreen
}
