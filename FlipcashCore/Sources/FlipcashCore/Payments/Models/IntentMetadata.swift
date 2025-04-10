//
//  IntentMetadata.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

public enum IntentMetadata: Equatable, Sendable {
    case openAccounts
    case sendPrivatePayment(PaymentMetadata)
    case sendPublicPayment(PaymentMetadata)
    case receivePaymentsPrivately
    case receivePaymentsPublicly(PaymentMetadata)
    case upgradePrivacy
}

// MARK: - Errors -

extension IntentMetadata {
    enum Error: Swift.Error {
        case unsupportedMetadataType
    }
}

// MARK: - Proto -

extension IntentMetadata {
    init(_ metadata: Code_Transaction_V2_Metadata) throws {
        guard let type = metadata.type else {
            throw Error.unsupportedMetadataType
        }
        
        switch type {
        case .openAccounts:
            self = .openAccounts
            
        case .receivePaymentsPublicly(let meta):
            
            self = .receivePaymentsPublicly(PaymentMetadata(
                exchangedFiat: try ExchangedFiat(meta.exchangeData)
            ))
            
        case .sendPublicPayment(let meta):
            self = .sendPublicPayment(PaymentMetadata(
                exchangedFiat: try ExchangedFiat(meta.exchangeData)
            ))
        }
    }
}
