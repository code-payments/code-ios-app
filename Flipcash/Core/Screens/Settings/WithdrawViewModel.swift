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
        PublicKey(base58: enteredAddress)
    }
    
    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            trace(.failure, components: "[Withdraw] Failed to parse amount string: \(enteredAmount)")
            return nil
        }
        
        let currency = ratesController.entryCurrency
        
        guard let rate = ratesController.rate(for: currency) else {
            trace(.failure, components: "[Withdraw] Rate not found for: \(currency)")
            return nil
        }
        
        guard let converted = try? Fiat(fiatDecimal: amount, currencyCode: currency) else {
            trace(.failure, components: "[Withdraw] Invalid amount for entry")
            return nil
        }
        
        return try! ExchangedFiat(converted: converted, rate: rate)
    }
    
    var canCompleteWithdrawal: Bool {
        if
            let enteredFiat = enteredFiat,
            let _ = enteredDestination,
            let destinationMetadata = destinationMetadata,
            session.hasSufficientFunds(for: enteredFiat),
            destinationMetadata.isValid
        {
            return true
        }
        return false
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
        
        Task {
            destinationMetadata = await client.fetchDestinationMetadata(destination: enteredDestination)
        }
    }
    
    private func completeWithdrawal() {
        guard let enteredFiat, let destinationMetadata else {
            return
        }
        
        withdrawButtonState = .loading
        Task {
            try await session.withdraw(
                exchangedFiat: enteredFiat,
                to: destinationMetadata.resolvedDestination
            )
            
            try await Task.delay(milliseconds: 500)
            withdrawButtonState = .success
            
            try await Task.delay(milliseconds: 500)
            showSuccessfulWithdrawalDialog()
        }
    }
    
    // MARK: - Actions -
    
    func amountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        guard session.hasSufficientFunds(for: exchangedFiat) else {
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
        dialogItem = .init(
            style: .destructive,
            title: "Are you sure?",
            subtitle: "Withdrawals are irreversible and cannot be undone once initiated.",
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
            let address = PublicKey(base58: string)
        else {
            return
        }
        
        enteredAddress = address.base58
    }
    
    // MARK: - Navigation -
    
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
            .okay { [weak self] in
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
            .okay()
        }
    }
}

enum WithdrawNavigationPath {
    case enterAddress
    case confirmation
}
