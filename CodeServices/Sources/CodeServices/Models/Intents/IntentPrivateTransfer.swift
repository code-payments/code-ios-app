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
    
    /// Amount requested to transfer
    let grossAmount: KinAmount
    
    /// Amount after fees are paid
    let netAmount: KinAmount
    
    let id: PublicKey
    let organizer: Organizer
    let destination: PublicKey
    let fee: Kin
    let additionalFees: [Fee]
    let isWithdrawal: Bool
    let tipAccount: TipAccount?
    let chatID: ChatID?
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, organizer: Organizer, destination: PublicKey, amount: KinAmount, fee: Kin, additionalFees: [Fee], isWithdrawal: Bool, tipAccount: TipAccount?, chatID: ChatID?) throws {
        
        // Fee must not exceed the amount
        // to transfer out
        guard amount.kin > fee else {
            throw Error.invalidFee
        }
        
        // Compute all the fees that will be
        // paid out of this transaction
        let conreteFees: [(feeAmount: Kin, destination: PublicKey)] = additionalFees.map {
            // Computed on the pre-Code fee amount
            let fee = amount.kin.calculateFee(bps: $0.bps)
            return (fee, $0.destination)
        }
        
        var netKin = amount.kin - fee
        
        // Apply the fees to the gross amount
        conreteFees.forEach { fee in
            netKin = netKin - fee.feeAmount
        }
        
        self.grossAmount = amount
        self.netAmount = KinAmount(
            kin: netKin,
            rate: amount.rate
        )
        
        self.id = rendezvous
        self.organizer = organizer
        self.destination = destination
        self.fee = fee
        self.additionalFees = additionalFees
        self.isWithdrawal = isWithdrawal
        self.tipAccount = tipAccount
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
        
        var feePayments: [ActionFeePayment] = []
        
        // Code Fee
        if fee > 0 {
            feePayments.append(
                ActionFeePayment(
                    kind: .code,
                    cluster: currentTray.outgoing.cluster,
                    amount: fee
                )
            )
        }
        
        // Additional Fees
        conreteFees.forEach { fee in
            feePayments.append(
                ActionFeePayment(
                    kind: .thirdParty(fee.destination),
                    cluster: currentTray.outgoing.cluster,
                    amount: fee.feeAmount
                )
            )
        }
        
        // 2. Transfer all collected funds from the temp
        // outgoing account to the destination account
        
        let outgoing = ActionWithdraw(
            kind: .noPrivacyWithdraw(netAmount.kin),
            cluster: currentTray.outgoing.cluster,
            destination: destination,
            tipAccount: tipAccount
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
            
            ActionWithdraw(
                kind: .closeDormantAccount(.outgoing),
                cluster: newOutgoing.cluster,
                destination: currentTray.owner.cluster.vaultPublicKey
            ),
        ]
        
        let endBalance = currentTray.slotsBalance
        
        guard startBalance - endBalance == grossAmount.kin else {
            throw Error.balanceMismatch
        }
        
        var group = ActionGroup()
        
        group.append(contentsOf: transfers)
        group.append(contentsOf: feePayments)
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
                
                if let tipAccount = tipAccount {
                    $0.isTip = true
                    $0.tippedUser = .with {
                        $0.platform = tipAccount.codePlatform
                        $0.username = tipAccount.username
                    }
                }
                
                if let chatID = chatID {
                    $0.isChat = true
                    $0.chatID = .with { $0.value = chatID.data }
                }
            }
        }
    }
}
