//
//  IntentDeposit.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

class IntentDeposit: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let amount: Kin
    let source: AccountType
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(source: AccountType, organizer: Organizer, amount: Kin) throws {
        let intentID = PublicKey.generate()!
        
        self.id = intentID
        self.organizer = organizer
        self.amount = amount
        self.source = source
        
        var currentTray = organizer.tray
        let startSlotBalance = currentTray.slotsBalance
        
        // 1. Move all funds from the primary
        // account to appropriate slots
        
        let transfers = try currentTray.receive(from: source, amount: amount).map { transfer in
            ActionTransfer(
                kind: .tempPrivacyTransfer,
                intentID: intentID,
                amount: transfer.kin,
                source: currentTray.cluster(for: transfer.from),
                destination: currentTray.cluster(for: transfer.to!).vaultPublicKey
            )
        }
        
        // 2. Redistribute the funds to prepare for
        // future transfers
        
        let redistributes = currentTray.redistribute().map { exchange in
            ActionTransfer(
                kind: .tempPrivacyExchange,
                intentID: intentID,
                amount: exchange.kin,
                source: currentTray.cluster(for: exchange.from),
                destination: currentTray.cluster(for: exchange.to!).vaultPublicKey // Exchanges always provide destination accounts
            )
        }
        
        let endSlotBalance = currentTray.slotsBalance

        // Ensure that balances are consistent
        // with what we expect these action to do
        guard endSlotBalance - startSlotBalance == amount else {
            throw Error.balanceMismatch
        }
        
        var group = ActionGroup()
        
        group.append(contentsOf: transfers)
        group.append(contentsOf: redistributes)
        
        self.actionGroup = group
        self.resultTray  = currentTray
    }
}

// MARK: - Errors -

extension IntentDeposit {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentDeposit {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.receivePaymentsPrivately = .with {
                $0.source = organizer.tray.cluster(for: source).vaultPublicKey.codeAccountID
                $0.quarks = amount.quarks
                $0.isDeposit = true
            }
        }
    }
}
