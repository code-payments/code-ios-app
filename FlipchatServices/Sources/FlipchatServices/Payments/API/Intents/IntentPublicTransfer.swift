//
//  IntentPublicTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI
import SwiftProtobuf

class IntentPublicTransfer: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let sourceCluster: AccountCluster
    let destination: PublicKey
    let amount: KinAmount
    let extendedMetadata: Google_Protobuf_Any?
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(organizer: Organizer, source: AccountType, destination: Destination, amount: KinAmount, extendedMetadata: Google_Protobuf_Any? = nil) throws {
        self.id = PublicKey.generate()!
        self.organizer = organizer
        self.sourceCluster = organizer.tray.cluster(for: source)
        self.amount = amount
        self.extendedMetadata = extendedMetadata
        
        switch destination {
        case .local(let accountType):
            self.destination = organizer.tray.cluster(for: accountType).vaultPublicKey
            
        case .external(let publicKey):
            self.destination = publicKey
        }
        
        var currentTray = organizer.tray
        
        // 1. Transfer all funds in the primary account
        // directly to the destination. This is a public
        // transfer so no buckets involved and no rotation
        // required.
        
        let transfer = ActionTransfer(
            kind: .noPrivacyTransfer,
            intentID: id,
            amount: amount.kin,
            source: sourceCluster,
            destination: self.destination
        )
        
        try currentTray.decrement(source, kin: amount.kin)
        
        // If moving funds to an already known account
        // we should update the balance accordingly
        if case .local(let accountType) = destination {
            try currentTray.increment(accountType, kin: amount.kin)
        }
        
        self.actionGroup = ActionGroup(actions: [transfer])
        self.resultTray  = currentTray
    }
}

extension IntentPublicTransfer {
    enum Destination: Equatable, Hashable {
        case local(AccountType)
        case external(PublicKey)
    }
}

// MARK: - Errors -

extension IntentPublicTransfer {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentPublicTransfer {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source =  sourceCluster.vaultPublicKey.codeAccountID
                $0.destination  = destination.codeAccountID
                $0.isWithdrawal = true
                $0.exchangeData = .with {
                    $0.quarks = amount.kin.quarks
                    $0.currency = amount.rate.currency.rawValue
                    $0.exchangeRate = amount.rate.fx.doubleValue
                    $0.nativeAmount = amount.fiat.doubleValue
                }
                
                if let extendedMetadata {
                    $0.extendedMetadata = .with {
                        $0.value = extendedMetadata
                    }
                }
            }
        }
    }
}
