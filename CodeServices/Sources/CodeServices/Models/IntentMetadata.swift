//
//  IntentMetadata.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum IntentMetadata: Equatable {
    case openAccounts
    case sendPrivatePayment(PaymentMetadata)
    case sendPublicPayment(PaymentMetadata)
    case receivePaymentsPrivately
    case receivePaymentsPublicly(PaymentMetadata)
    case upgradePrivacy
    case migrateToPrivacy2022
}

public struct PaymentMetadata: Equatable {
    
    public let amount: KinAmount
    
    init(amount: KinAmount) {
        self.amount = amount
    }
}
