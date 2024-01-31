//
//  IntentReceive.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentReceive: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let amount: Kin
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(organizer: Organizer, amount: Kin) throws {
        let intentID = PublicKey.generate()!
        
        self.id = intentID
        self.organizer = organizer
        self.amount = amount
        
        var currentTray = organizer.tray
        let startSlotBalance = currentTray.slotsBalance
        let startIncomingBalance = currentTray.availableIncomingBalance
        
        // 1. Move all funds from the incoming
        // account to appropriate slots
        
        let transfers = try currentTray.receive(from: .incoming, amount: amount).map { transfer in
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
        
        // 3. Rotate incoming account
        
        let oldIncoming = currentTray.incoming
        currentTray.incrementIncoming()
        let newIncoming = currentTray.incoming
        
        let rotation: [ActionType] = [
            
            ActionCloseEmptyAccount(
                type: .incoming,
                cluster: oldIncoming.cluster
            ),
            
            ActionOpenAccount(
                owner: organizer.tray.owner.cluster.authority.keyPair.publicKey,
                type: .incoming,
                accountCluster: newIncoming.cluster
            ),
            
            ActionWithdraw(
                kind: .closeDormantAccount(.incoming),
                cluster: newIncoming.cluster,
                destination: organizer.tray.owner.cluster.vaultPublicKey
            )
        ]
        
        let endSlotBalance = currentTray.slotsBalance
        let endIncomingBalance = currentTray.availableIncomingBalance

        // Ensure that balances are consistent
        // with what we expect these action to do
        guard endSlotBalance - startSlotBalance == amount else {
            throw Error.balanceMismatch
        }
        
        guard startIncomingBalance - endIncomingBalance == amount else {
            throw Error.balanceMismatch
        }
        
        var group = ActionGroup()
        
        group.append(contentsOf: transfers)
        group.append(contentsOf: redistributes)
        group.append(contentsOf: rotation)
        
        self.actionGroup = group
        self.resultTray  = currentTray
    }
}

// MARK: - Errors -

extension IntentReceive {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentReceive {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.receivePaymentsPrivately = .with {
                $0.source = organizer.tray.incoming.cluster.vaultPublicKey.codeAccountID
                $0.quarks = amount.quarks
                $0.isDeposit = false
            }
        }
    }
}
