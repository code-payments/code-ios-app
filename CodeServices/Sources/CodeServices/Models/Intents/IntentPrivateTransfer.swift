//
//  IntentPrivateTransfer.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentPrivateTransfer: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let destination: PublicKey
    let amount: KinAmount
    let fee: Kin
    let isWithdrawal: Bool
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, organizer: Organizer, destination: PublicKey, amount: KinAmount, fee: Kin = 0, isWithdrawal: Bool) throws {
        
        // Fee must not exceed the amount
        // to transfer out
        guard amount.kin > fee else {
            throw Error.invalidFee
        }
        
        self.id = rendezvous
        self.organizer = organizer
        self.destination = destination
        self.amount = amount
        self.fee = fee
        self.isWithdrawal = isWithdrawal
        
        var currentTray = organizer.tray
        let startBalance = currentTray.slotsBalance
        
        // 1. Move all funds from bucket accounts into the
        // outgoing account and prepare to transfer
        
        let transfers = try currentTray.transfer(amount: amount.kin).map { transfer in
            let sourceCluster = currentTray.cluster(for: transfer.from)
            
            // If the transfer is to another bucket, it's an internal
            // exchange. Otherwise, it is considered a transfer.
            if case .bucket(let slotType) = transfer.to {
                return ActionTransfer(
                    kind: .tempPrivacyExchange,
                    intentID: rendezvous,
                    amount: transfer.kin,
                    source: sourceCluster,
                    destination: currentTray.slot(for: slotType).cluster.timelockAccounts.vault.publicKey
                )
                
            } else {
                return ActionTransfer(
                    kind: .tempPrivacyTransfer,
                    intentID: rendezvous,
                    amount: transfer.kin,
                    source: sourceCluster,
                    destination: currentTray.outgoing.cluster.timelockAccounts.vault.publicKey
                )
            }
        }
        
        let feePayment: ActionFeePayment?
        if fee > 0 {
            feePayment = ActionFeePayment(
                cluster: currentTray.outgoing.cluster,
                amount: fee
            )
        } else {
            feePayment = nil
        }
        
        // 2. Transfer all collected funds from the temp
        // outgoing account to the destination account
        
        let outgoing = ActionWithdraw(
            kind: .noPrivacyWithdraw(amount.kin - fee),
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
                destination: currentTray.cluster(for: exchange.to!).timelockAccounts.vault.publicKey // Exchanges always provide destination accounts
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
            
            ActionWithdraw(
                kind: .closeDormantAccount(.outgoing),
                cluster: newOutgoing.cluster,
                destination: currentTray.owner.cluster.timelockAccounts.vault.publicKey
            ),
        ]
        
        let endBalance = currentTray.slotsBalance
        
        guard startBalance - endBalance == amount.kin else {
            throw Error.balanceMismatch
        }
        
        var group = ActionGroup()
        
        group.append(contentsOf: transfers)
        
        if let feePayment {
            group.append(feePayment)
        }
        
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
                    $0.quarks = amount.kin.quarks
                    $0.currency = amount.rate.currency.rawValue
                    $0.exchangeRate = amount.rate.fx.doubleValue
                    $0.nativeAmount = amount.fiat.doubleValue
                }
            }
        }
    }
}
