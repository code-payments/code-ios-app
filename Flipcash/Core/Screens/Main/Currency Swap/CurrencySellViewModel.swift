//
//  CurrencySellViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor
class CurrencySellViewModel: ObservableObject {
    @Published var enteredAmount: String = ""
    @Published var path: [CurrencySellPath] = []
    let currencyMetadata: StoredMintMetadata
        
    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else { return nil }
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else { return nil }
        guard let tvl = currencyMetadata.coreMintLocked else { return nil }
                
        return ExchangedFiat.computeFromEntered(
            amount: amount,
            rate: ratesController.rateForEntryCurrency(),
            mint: currencyMetadata.mint,
            tvl: tvl
        )
    }
        
    var canPerformAction: Bool {
        return enteredFiat != nil
    }
    
    var screenTitle: String {
        return "Amount To Sell"
    }
    
    var maxPossibleAmount: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero = try! ExchangedFiat(underlying: 0, rate: entryRate, mint: currencyMetadata.mint)
        
        guard let balance = session.balance(for: currencyMetadata.mint) else {
            return zero
        }
        
        return balance.computeExchangedValue(with: entryRate)
    }
    
    private let session: Session
    private let ratesController: RatesController
    
    // MARK: - Init -
    
    init(currencyMetadata: StoredMintMetadata, container: Container, sessionContainer: SessionContainer) {
        self.currencyMetadata = currencyMetadata
        self.session = sessionContainer.session
        self.ratesController  = sessionContainer.ratesController
    }
        
    // MARK: - Actions -
        
    func showConfirmationScreen() {
        guard enteredFiat != nil else {
            return
        }

        // Navigate to the next screen
        path.append(.confirmation)
    }
                    
    // MARK: - Reset -
    
    func reset() {
        enteredAmount = ""
        path = []
    }
}

enum CurrencySellPath: Hashable {
    case confirmation
}
