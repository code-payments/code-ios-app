//
//  IntentMetadata.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum IntentMetadata: Equatable, Sendable {
    case openAccounts
    case sendPrivatePayment(PaymentMetadata)
    case sendPublicPayment(PaymentMetadata)
    case receivePaymentsPrivately
    case receivePaymentsPublicly(PaymentMetadata)
    case upgradePrivacy
}

public struct PaymentMetadata: Equatable, Sendable {
    
    public let amount: Fiat
    
    init(amount: Fiat) {
        self.amount = amount
    }
}
