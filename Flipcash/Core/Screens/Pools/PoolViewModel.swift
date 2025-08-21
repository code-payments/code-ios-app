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
    
    @Published var poolListPath: [PoolListPath] = []
    
    @Published var enteredPoolName: String = ""
    
    @Published var enteredPoolAmount: String = ""
    
    @Published var createPoolButtonState: ButtonState = .normal
    
    @Published var isShowingCreatePoolFlow: Bool = false
    
    @Published var isShowingBetConfirmation: PoolResoltion?
    
    @Published var isShowingPoolList: Bool = false {
        didSet {
            if !isShowingPoolList {
                poolListPath = []
            }
        }
    }
    
    @Published var dialogItem: DialogItem?
    
    var canCreatePool: Bool {
        isEnteredPoolNameValid && (enteredPoolFiat?.usdc ?? 0) > 0
    }
    
    var enteredPoolNameSantized: String {
        enteredPoolName
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isEnteredPoolNameValid: Bool {
        enteredPoolNameSantized.count > 3
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
        
        guard let enteredFiat = try? Fiat(fiatDecimal: amount, currencyCode: currency) else {
            trace(.failure, components: "[Withdraw] Invalid amount for entry")
            return nil
        }
        
        guard let exchangedFiat = try? ratesController.exchangedFiat(for: enteredFiat) else {
            trace(.failure, components: "[Withdraw] Rate not found for: \(currency)")
            return nil
        }
        
        return exchangedFiat
    }
    
    private let container: Container
    private let session: Session
    private let ratesController: RatesController
    private let poolController: PoolController
    
    // MARK: - Init -
    
    init(container: Container, session: Session, ratesController: RatesController, poolController: PoolController) {
        self.container       = container
        self.session         = session
        self.ratesController = ratesController
        self.poolController  = poolController
    }
    
    // MARK: - Pools -
    
    func syncPools() {
        Task {
            try await poolController.syncPools()
        }
    }
    
    // MARK: - Create Actions -
    
    func startPoolCreationFlowAction() {
        
        // Reset all state before
        // pool creation starts
        enteredPoolName   = ""
        enteredPoolAmount = ""
        createPoolPath    = []
        
        isShowingCreatePoolFlow = true
    }
    
    func submitPoolNameAction() {
        navigateToEnterPoolAmount()
    }
    
    func submitPoolAmountAction() {
        guard let buyIn = enteredPoolFiat?.converted else {
            return
        }
        
        guard let limit = session.singleTransactionLimit, buyIn.quarks <= limit.quarks else {
            showPoolCostTooHighError()
            return
        }
        
        navigateToPoolSummary()
    }
    
    func createPoolAction() {
        guard let buyIn = enteredPoolFiat?.converted else {
            return
        }
        
        createPoolButtonState = .loading
        Task {
            do {
                let poolID = try await poolController.createPool(
                    name: enteredPoolNameSantized,
                    buyIn: buyIn
                )
                try await Task.delay(milliseconds: 250)
                
                navigateToPoolDetails(poolID: poolID)
                Analytics.poolCreated(id: poolID)
                
                createPoolButtonState = .success
                try await Task.delay(milliseconds: 250)
                
                isShowingCreatePoolFlow = false
                
                try await Task.delay(milliseconds: 250)
                createPoolButtonState = .normal
                
            } catch {
                ErrorReporting.captureError(error)
                createPoolButtonState = .normal
            }
        }
    }
    
    // MARK: - Pool Actions -
    
    func selectPoolAction(poolID: PublicKey) {
        navigateToPoolDetails(poolID: poolID)
    }
    
    func selectBetAction(outcome: PoolResoltion, for pool: StoredPool) {
        guard let exchangedBuyIn = try? ratesController.exchangedFiat(for: pool.buyIn) else {
            return
        }
        
        guard session.hasSufficientFunds(for: exchangedBuyIn) else {
            showInsufficientBalanceError()
            return
        }
        
        isShowingBetConfirmation = outcome
    }
    
    func betAction(pool: StoredPool, outcome: PoolResoltion) async throws {
        do {
            try await poolController.createBet(
                pool: pool,
                outcome: outcome
            )
            
            Analytics.poolPlaceBet(id: pool.id)
            
        } catch {
            ErrorReporting.captureError(error)
            throw error
        }
    }
    
    func declarOutcomeAction(pool: StoredPool, outcome: PoolResoltion) async throws {
        do {
            try await poolController.declareOutcome(
                pool: pool,
                outcome: outcome
            )
            
            Analytics.poolDeclareOutcome(id: pool.id)
            
        } catch {
            ErrorReporting.captureError(error)
            throw error
        }
    }
    
    // MARK: - Presentation -
    
    func showPoolList() {
        isShowingPoolList = true
    }
    
    func openPoolFromDeeplink(rendezvous: KeyPair) {
        updatePool(
            poolID: rendezvous.publicKey,
            rendezvous: rendezvous
        )
        
        navigateToPoolDetails(poolID: rendezvous.publicKey)
        showPoolList()
        
        Analytics.poolOpenedFromDeeplink(id: rendezvous.publicKey)
    }
    
    // MARK: - Updates -
    
    func updatePool(poolID: PublicKey, rendezvous: KeyPair?) {
        Task {
            try await poolController.updatePool(
                poolID: poolID,
                rendezvous: rendezvous
            )
        }
    }
    
    // MARK: - Create Pool Navigation -
    
    private func navigateToEnterPoolAmount() {
        createPoolPath.append(.enterPoolAmount)
    }
    
    private func navigateToPoolSummary() {
        createPoolPath.append(.poolSummary)
    }
    
    // MARK: - Pool List Navigation -
    
    private func navigateToPoolDetails(poolID: PublicKey) {
        poolListPath.append(.poolDetails(poolID))
    }
    
    // MARK: - Errors -
    
    private func showPoolCostTooHighError() {
        dialogItem = .init(
            style: .destructive,
            title: "Cost Limit Too High",
            subtitle: "Your pool's cost to join is too high. Enter a smaller amount and try again.",
            dismissable: true
        ) {
            .okay(kind: .standard)
        }
    }
    
    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "Insufficient Balance",
            subtitle: "You need more funds to join this Pool",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

// MARK: - Error -

extension PoolViewModel {
    enum Error: Swift.Error {
        case insufficientFundsForBet
    }
}

// MARK: - Path -

enum CreatePoolPath {
    case enterPoolAmount
    case poolSummary
}

enum PoolListPath: Hashable {
    case poolDetails(PublicKey)
}

// MARK: - Mock -

extension PoolViewModel {
    static let mock: PoolViewModel = .init(container: .mock, session: .mock, ratesController: .mock, poolController: .mock)
}
