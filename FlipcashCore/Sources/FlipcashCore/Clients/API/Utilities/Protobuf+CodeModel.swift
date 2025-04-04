//
//  Protobuf+Model.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

// MARK: - Serialize -

extension SwiftProtobuf.Message {
    public func sign(with owner: KeyPair) -> Code_Common_V1_Signature {
        var signature = Code_Common_V1_Signature()
        signature.value = owner.sign(try! serializedData()).data
        return signature
    }
}

extension PublicKey {
    public var codeAccountID: Code_Common_V1_SolanaAccountId {
        var accountID = Code_Common_V1_SolanaAccountId()
        accountID.value = data
        return accountID
    }
    
    public var codeRendezvousKey: Code_Messaging_V1_RendezvousKey {
        var rendezvousKey = Code_Messaging_V1_RendezvousKey()
        rendezvousKey.value = data
        return rendezvousKey
    }
    
    public var codeIntentID: Code_Common_V1_IntentId {
        var paymentID = Code_Common_V1_IntentId()
        paymentID.value = data
        return paymentID
    }
}

extension Signature {
    
    public var codeClientSignature: Code_Common_V1_Signature {
        var signature = Code_Common_V1_Signature()
        signature.value = data
        return signature
    }
}

extension ID {
    public var codeCursor: Code_Transaction_V2_Cursor {
        var cursor = Code_Transaction_V2_Cursor()
        cursor.value = data
        return cursor
    }
}

extension IntentMetadata {
    init?(_ metadata: Code_Transaction_V2_Metadata) {
        guard let type = metadata.type else {
            return nil
        }
        
        switch type {
        case .openAccounts:
            self = .openAccounts
            
        case .receivePaymentsPublicly(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .receivePaymentsPublicly(metadata)
            
        case .sendPublicPayment(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .sendPublicPayment(metadata)
        }
    }
    
    private static func paymentMetadata(for exchangeData: Code_Transaction_V2_ExchangeData) -> PaymentMetadata? {
        guard let amount = exchangeData.fiat else {
            return nil
        }
        
        return PaymentMetadata(amount: amount)
    }
}

extension Code_Transaction_V2_ExchangeData {
    var fiat: FiatAmount? {
        guard let currency = CurrencyCode(currencyCode: currency) else {
            return nil
        }
        
        return FiatAmount(
            fiat: Fiat(
                quarks: quarks,
                currencyCode: .usd
            ),
            rate: Rate(
                fx: Decimal(exchangeRate),
                currency: currency
            )
        )
    }
}
