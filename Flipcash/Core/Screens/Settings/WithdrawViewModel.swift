//
//  WithdrawViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-15.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor
class WithdrawViewModel: ObservableObject {
    
    @Published var path: [WithdrawNavigationPath] = []
    
    @Published var withdrawButtonState: ButtonState = .normal
    
    @Published var selectedBalance: ExchangedBalance?
    
    @Published var enteredAmount: String = ""
    @Published var enteredAddress: String = "" {
        didSet {
            if enteredDestination != nil {
                fetchDestinationMetadata()
            }
        }
    }
    
    @Published var destinationMetadata: DestinationMetadata?
    
    @Published var dialogItem: DialogItem?
    
    var enteredDestination: PublicKey? {
        try? PublicKey(base58: enteredAddress)
    }
    
    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let selectedBalance else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }
        
        let mint = selectedBalance.stored.mint
        
        // Only applies for bonded tokens
        if mint != .usdc {
            guard let supplyFromBonding = selectedBalance.stored.supplyFromBonding else {
                return nil
            }
            
            return ExchangedFiat.computeFromEntered(
                amount: amount,
                rate: .oneToOne, // Withdrawals are forced to usd
                mint: mint,
                supplyFromBonding: supplyFromBonding
            )
        } else {
            return try! ExchangedFiat(
                usdc: .init(
                    fiatDecimal: amount,
                    currencyCode: .usd,
                    decimals: mint.mintDecimals
                ),
                rate: .oneToOne,
                mint: mint
            )
        }
    }
    
    var negativeWithdrawableAmount: Fiat? {
        guard let enteredFiat = enteredFiat else {
            return nil
        }
        
        guard let exchangedFee else {
            return nil
        }
        
        let feeInUnderlying = exchangedFee.usdc
        
        guard feeInUnderlying.quarks >= enteredFiat.usdc.quarks else {
            return nil
        }
        
        return try! enteredFiat.subtracting(
            fee: feeInUnderlying,
            invert: true // fee - enteredFiat
        ).converted
    }
    
    var withdrawableAmount: ExchangedFiat? {
        guard let enteredFiat = enteredFiat else {
            return nil
        }
        
        guard let destinationMetadata else {
            return nil
        }
        
        if destinationMetadata.requiresInitialization && destinationMetadata.fee.quarks > 0 {
            if enteredFiat.mint == .usdc {
                return try? enteredFiat.subtracting(fee: destinationMetadata.fee)
            } else {
                guard let exchangedFee else {
                    return nil
                }
                
                return try? enteredFiat.subtracting(fee: exchangedFee.usdc)
            }
        } else {
            return enteredFiat
        }
    }
    
//    var hasSufficientFunds: Bool {
//        session.hasSufficientFunds(for: enteredFiat!).0
//    }
    
    var canCompleteWithdrawal: Bool {
        if
            let enteredFiat = enteredFiat,
            let _ = enteredDestination,
            let destinationMetadata = destinationMetadata,
            session.hasSufficientFunds(for: enteredFiat).0,
            destinationMetadata.isValid
        {
            return true
        }
        return false
    }
    
    var withdrawTitle: String {
        if let balance = selectedBalance {
            return "Withdraw \(balance.stored.name)"
        } else {
            return "Withdraw"
        }
    }
    
    var maxWithdrawLimit: Fiat {
        guard let mint = selectedBalance?.stored.mint else {
            return 0
        }
        
        let aggregateBalance = AggregateBalance(
            entryRate: .oneToOne, // Always USD
            balanceRate: ratesController.rateForBalanceCurrency(),
            balances: session.balances
        )
        
        guard let balance = aggregateBalance.entryBalance(for: mint) else {
            return 0
        }
        
        return balance.exchangedFiat.converted
    }
    
    private var exchangedFee: ExchangedFiat? {
        guard let enteredFiat = enteredFiat else {
            return nil
        }
        
        guard let selectedBalance else {
            return nil
        }
        
        guard let currentSupply = selectedBalance.stored.supplyFromBonding else {
            return nil
        }
        
        guard let destinationMetadata else {
            return nil
        }
        
        // TODO: Using tokensForValueExchange, should it equivalent to sell pricing?
        return ExchangedFiat.computeFromEntered(
            amount: destinationMetadata.fee.decimalValue,
            rate: .oneToOne, // Fee is charged in USDC
            mint: enteredFiat.mint,
            supplyFromBonding: currentSupply
        )
    }
    
    private var amountToWithdraw: ExchangedFiat?
    
    private let isPresented: Binding<Bool>
    private let container: Container
    private let client: Client
    private let session: Session
    private let ratesController: RatesController
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self.isPresented     = isPresented
        self.container       = container
        self.client          = container.client
        self.session         = sessionContainer.session
        self.ratesController = sessionContainer.ratesController
    }
    
    // MARK: - Metadata -
    
    private func fetchDestinationMetadata() {
        guard let enteredDestination else {
            return
        }
        
        guard let mint = selectedBalance?.stored.mint else {
            return
        }
        
        Task {
            destinationMetadata = await client.fetchDestinationMetadata(destination: enteredDestination, mint: mint)
        }
    }
    
    private func completeWithdrawal() {
        guard let enteredFiat, let destinationMetadata else {
            return
        }
        
        let fee: Fiat
        if enteredFiat.mint == .usdc {
            fee = destinationMetadata.fee
        } else {
            fee = exchangedFee?.usdc ?? 0
        }
        
        withdrawButtonState = .loading
        Task {
            do {
                try await session.withdraw(
                    exchangedFiat: enteredFiat,
                    fee: fee,
                    to: destinationMetadata
                )
                
                try await Task.delay(milliseconds: 500)
                withdrawButtonState = .success
                
                try await Task.delay(milliseconds: 500)
                showSuccessfulWithdrawalDialog()
                
            } catch {
                withdrawButtonState = .normal
            }
        }
    }
    
    // MARK: - Actions -
    
    func amountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        let (hasSufficientFunds, _) = session.hasSufficientFunds(for: exchangedFiat)
        
        guard hasSufficientFunds else {
            showInsufficientBalanceError()
            return
        }
        
        amountToWithdraw = exchangedFiat
        pushEnterAddressScreen()
    }
    
    func addressEnteredAction() {
        pushConfirmationScreen()
    }
    
    func completeWithdrawalAction() {
        guard negativeWithdrawableAmount == nil else {
            dialogItem = .init(
                style: .destructive,
                title: "Withdrawal Amount Too Small",
                subtitle: "Your withdrawal amount is too small to cover the one time fee. Please try a different amount",
                dismissable: true
            ) {
                .okay(kind: .standard) { [weak self] in
                    self?.resetEnteredAmount()
                    self?.popToEnterAmount()
                }
            }
            return
        }
        
        dialogItem = .init(
            style: .destructive,
            title: "Are You Sure?",
            subtitle: "Withdrawals are irreversible and cannot be undone once initiated",
            dismissable: true,
            actions: {
                .destructive("Withdraw") { [weak self] in
                    self?.completeWithdrawal()
                };
                .cancel()
            }
        )
    }
    
    func pasteFromClipboardAction() {
        guard
            let string = UIPasteboard.general.string,
            let address = try? PublicKey(base58: string)
        else {
            return
        }
        
        enteredAddress = address.base58
    }
    
    // MARK: - Reset -
    
    private func resetEnteredAmount() {
        enteredAmount = ""
    }
    
    // MARK: - Navigation -
    
    private func popToEnterAmount() {
        path = [.enterAmount]
    }
    
    func pushEnterAmountScreen() {
        path.append(.enterAmount)
    }
    
    private func pushEnterAddressScreen() {
        path.append(.enterAddress)
    }
    
    private func pushConfirmationScreen() {
        path.append(.confirmation)
    }
    
    // MARK: - Dialogs -
    
    private func showSuccessfulWithdrawalDialog() {
        dialogItem = .init(
            style: .success,
            title: "Withdrawal Successful",
            subtitle: "Your withdrawal has been processed. It may take a few minutes for your funds to show up in your destination wallet.",
            dismissable: false
        ) {
            .okay(kind: .standard) { [weak self] in
                self?.isPresented.wrappedValue = false
            }
        }
    }
    
    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "Insufficient Balance",
            subtitle: "Please enter a lower amount and try again",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

enum WithdrawNavigationPath {
    case enterAmount
    case enterAddress
    case confirmation
}
