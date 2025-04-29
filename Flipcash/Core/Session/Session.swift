//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashUI
import FlipcashCore

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published private(set) var balance: Fiat = 0

    let owner: AccountCluster
    let userID: UserID
    
    var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
    var exchangedBalance: ExchangedFiat {
        try! ExchangedFiat(
            usdc: balance,
            rate: ratesController.rateForBalanceCurrency()
        )
    }
    
    var exchangedEntryBalance: ExchangedFiat {
        try! ExchangedFiat(
            usdc: balance,
            rate: ratesController.rateForEntryCurrency()
        )
    }
    
    private let container: Container
    private let client: Client
    private let ratesController: RatesController
    
    private var poller: Poller!
    
    // MARK: - Init -
    
    init(container: Container, owner: AccountCluster, userID: UserID) {
        self.container       = container
        self.client          = container.client
        self.ratesController = container.ratesController
        self.owner           = owner
        self.userID          = userID
        
        registerPoller()
    }
    
    func prepareForLogout() {
        
    }
    
    // MARK: - Poller -
    
    private func registerPoller() {
        poller = Poller(seconds: 10, fireImmediately: true) { [weak self] in
            Task {
                try await self?.poll()
            }
        }
    }
    
    private func poll() async throws {
        try await fetchBalance()
    }
    
    // MARK: - Balance -
    
    private func fetchBalance() async throws {
        balance = try await client.fetchBalance(owner: ownerKeyPair)
    }
}

// MARK: - Mock -

extension Session {
    static let mock = Session(
        container: .mock,
        owner: .init(authority: .derive(using: .primary(), mnemonic: .mock)),
        userID: UUID()
    )
}
