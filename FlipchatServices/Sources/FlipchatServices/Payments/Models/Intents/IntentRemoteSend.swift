//
//  IntentRemoteSend.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentRemoteSend: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let giftCard: GiftCardAccount
    let amount: KinAmount
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, organizer: Organizer, giftCard: GiftCardAccount, amount: KinAmount) throws {
        self.id = rendezvous
        self.organizer = organizer
        self.giftCard = giftCard
        self.amount = amount
        
        var currentTray = organizer.tray
        let startBalance = currentTray.slotsBalance
        
        // 1. Open gift card account
        
        let openGiftCard = ActionOpenAccount(
            owner: giftCard.cluster.authority.keyPair.publicKey,
            type: .remoteSend,
            accountCluster: giftCard.cluster
        )
        
        // 2. Move all funds from bucket accounts into the
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
        
        // 3. Transfer all collected funds from the temp
        // outgoing account to the destination account
        
        let outgoing = ActionWithdraw(
            kind: .noPrivacyWithdraw(amount.kin),
            cluster: currentTray.outgoing.cluster,
            destination: giftCard.cluster.vaultPublicKey
        )
        
        // 4. Redistribute the funds to optimize for a
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
        
        // 5. Rotate the outgoing account
        
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
        
        // 6. Close gift card account
        
        let closeGiftCard = ActionWithdraw(
            kind: .closeDormantAccount(.remoteSend),
            cluster: giftCard.cluster,
            destination: currentTray.owner.cluster.vaultPublicKey
        )
        
        let endBalance = currentTray.slotsBalance
        
        guard startBalance - endBalance == amount.kin else {
            throw Error.balanceMismatch
        }
        
        var group = ActionGroup()
        
        group.append(openGiftCard)
        group.append(contentsOf: transfers)
        group.append(outgoing)
        group.append(contentsOf: redistributes)
        group.append(contentsOf: rotation)
        group.append(closeGiftCard)
        
        self.actionGroup = group
        self.resultTray  = currentTray
    }
}

// MARK: - Errors -

extension IntentRemoteSend {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentRemoteSend {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPrivatePayment = .with {
                $0.destination  = giftCard.cluster.vaultPublicKey.codeAccountID
                $0.isWithdrawal = false
                $0.isRemoteSend = true
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
