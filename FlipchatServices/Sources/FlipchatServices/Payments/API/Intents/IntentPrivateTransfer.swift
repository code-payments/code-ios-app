//
//  IntentPrivateTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

class IntentPrivateTransfer: IntentType {
    
    /// Amount requested to transfer
    let grossAmount: KinAmount
    
    /// Amount after fees are paid
    let netAmount: KinAmount
    
    let id: PublicKey
    let organizer: Organizer
    let destination: PublicKey
    let isWithdrawal: Bool
    let chatID: ChatID?
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, organizer: Organizer, destination: PublicKey, amount: KinAmount, isWithdrawal: Bool, chatID: ChatID?) throws {
        self.grossAmount = amount
        self.netAmount = amount
        self.id = rendezvous
        self.organizer = organizer
        self.destination = destination
        self.isWithdrawal = isWithdrawal
        self.chatID = chatID
        
        var currentTray = organizer.tray
        let startBalance = currentTray.slotsBalance
        
        // 1. Move all funds from bucket accounts into the
        // outgoing account and prepare to transfer
        
        let transfers = try currentTray.transfer(amount: grossAmount.kin).map { transfer in
            let sourceCluster = currentTray.cluster(for: transfer.from)
            
            // If the transfer is to another bucket, it's an internal
            // exchange. Otherwise, it is considered a transfer.
            if case .bucket(let slotType) = transfer.to {
                return ActionTransfer(
                    kind: .tempPrivacyExchange,
                    intentID: rendezvous,
                    amount: transfer.kin,
                    source: sourceCluster,
                    destination: currentTray.slot(for: slotType).cluster.vaultPublicKey
                )
                
            } else {
                return ActionTransfer(
                    kind: .tempPrivacyTransfer,
                    intentID: rendezvous,
                    amount: transfer.kin,
                    source: sourceCluster,
                    destination: currentTray.outgoing.cluster.vaultPublicKey
                )
            }
        }
        
        // 2. Transfer all collected funds from the temp
        // outgoing account to the destination account
        
        let outgoing = ActionWithdraw(
            kind: .noPrivacyWithdraw(netAmount.kin),
            cluster: currentTray.outgoing.cluster,
            destination: destination
        )
        
        // 3. Redistribute the funds to optimize for a
        // subsequent payment out of the buckets
        
        let redistributes = currentTray.redistribute().map { exchange in
            ActionTransfer(
                kind: .tempPrivacyExchange,
                intentID: rendezvous,
                amount: exchange.kin,
                source: currentTray.cluster(for: exchange.from),
                destination: currentTray.cluster(for: exchange.to!).vaultPublicKey // Exchanges always provide destination accounts
            )
        }
        
        // 4. Rotate the outgoing account
        
        currentTray.incrementOutgoing()
        let newOutgoing = currentTray.outgoing
        
        let rotation: [ActionType] = [
            ActionOpenAccount(
                owner: currentTray.owner.cluster.authority.keyPair.publicKey,
                type: .outgoing,
                accountCluster: newOutgoing.cluster
            ),
            
//            ActionWithdraw(
//                kind: .closeDormantAccount(.outgoing),
//                cluster: newOutgoing.cluster,
//                destination: currentTray.owner.cluster.vaultPublicKey
//            ),
        ]
        
        let endBalance = currentTray.slotsBalance
        
        guard startBalance - endBalance == grossAmount.kin else {
            throw Error.balanceMismatch
        }
        
        var group = ActionGroup()
        
        group.append(contentsOf: transfers)
        group.append(outgoing)
        group.append(contentsOf: redistributes)
        group.append(contentsOf: rotation)
        
        self.actionGroup = group
        self.resultTray  = currentTray
    }
}

// MARK: - Errors -

extension IntentPrivateTransfer {
    enum Error: Swift.Error {
        case invalidFee
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentPrivateTransfer {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPrivatePayment = .with {
                $0.destination  = destination.codeAccountID
                $0.isWithdrawal = isWithdrawal
                $0.exchangeData = .with {
                    $0.quarks = grossAmount.kin.quarks
                    $0.currency = grossAmount.rate.currency.rawValue
                    $0.exchangeRate = grossAmount.rate.fx.doubleValue
                    $0.nativeAmount = grossAmount.fiat.doubleValue
                }
                
//                if let chatID = chatID {
//                    $0.isChat = true
//                    $0.chatID = .with { $0.value = chatID.data }
//                }
            }
        }
    }
}
