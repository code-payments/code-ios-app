//
//  PoolViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import StoreKit

@MainActor
class PoolViewModel: ObservableObject {

    @Published var createPoolPath: [CreatePoolPath] = []
    
    @Published var enteredPoolName: String = ""
    
    @Published var enteredPoolAmount: String = ""
    
    @Published var isShowingCreatePoolFlow: Bool = false
    
    var canCreatePool: Bool {
        isEnteredPoolNameValid && (enteredPoolFiat?.usdc ?? 0) > 0
    }
    
    var isEnteredPoolNameValid: Bool {
        enteredPoolName.count > 3
    }
    
    var enteredPoolFiat: ExchangedFiat? {
        guard !enteredPoolAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredPoolAmount) else {
            trace(.failure, components: "[Withdraw] Failed to parse amount string: \(enteredPoolAmount)")
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
        
        return try! ExchangedFiat(
            converted: converted,
            rate: rate
        )
    }
    
    private let container: Container
    private let ratesController: RatesController
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.container       = container
        self.ratesController = sessionContainer.ratesController
    }
    
    // MARK: - Actions -
    
    func startPoolCreationFlowAction() {
        isShowingCreatePoolFlow = true
    }
    
    func submitPoolNameAction() {
        navigateToEnterPoolAmount()
    }
    
    func submitPoolAmountAction() {
        navigateToPoolSummary()
    }
    
    func createPoolAction() {
        
    }
    
    // MARK: - Navigation -
    
    private func navigateToEnterPoolAmount() {
        createPoolPath.append(.enterPoolAmount)
    }
    
    private func navigateToPoolSummary() {
        createPoolPath.append(.poolSummary)
    }
}

// MARK: - Path -

enum CreatePoolPath {
    case enterPoolAmount
    case poolSummary
}
