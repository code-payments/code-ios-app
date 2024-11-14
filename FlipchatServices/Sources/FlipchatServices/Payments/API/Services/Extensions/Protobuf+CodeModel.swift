//
//  Protobuf+Model.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI
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
    public var codeUserID: Code_Common_V1_UserId {
        var userID = Code_Common_V1_UserId()
        userID.value = data
        return userID
    }
    
    public var codeContainerID: Code_Common_V1_DataContainerId {
        var userID = Code_Common_V1_DataContainerId()
        userID.value = data
        return userID
    }
    
    public var codeCursor: Code_Transaction_V2_Cursor {
        var cursor = Code_Transaction_V2_Cursor()
        cursor.value = data
        return cursor
    }
}

extension String {
    public var codeVerificationCode: Code_Phone_V1_VerificationCode {
        var verificationCode = Code_Phone_V1_VerificationCode()
        verificationCode.value = self
        return verificationCode
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
            
        case .receivePaymentsPrivately:
            self = .receivePaymentsPrivately
            
        case .receivePaymentsPublicly(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .receivePaymentsPublicly(metadata)
            
        case .upgradePrivacy:
            self = .upgradePrivacy
            
        case .sendPrivatePayment(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .sendPrivatePayment(metadata)
            
        case .sendPublicPayment(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .sendPublicPayment(metadata)
            
        case .establishRelationship:
            // TODO: Create relevant metadata
            return nil
        }
    }
    
    private static func paymentMetadata(for exchangeData: Code_Transaction_V2_ExchangeData) -> PaymentMetadata? {
        guard let amount = exchangeData.kinAmount else {
            return nil
        }
        
        return PaymentMetadata(amount: amount)
    }
}

extension Code_Transaction_V2_ExchangeData {
    var kinAmount: KinAmount? {
        guard let currency = CurrencyCode(currencyCode: currency) else {
            return nil
        }
        
        return KinAmount(
            kin: Kin(quarks: quarks),
            rate: Rate(
                fx: Decimal(exchangeRate),
                currency: currency
            )
        )
    }
}
