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
    case sendPayment(PaymentMetadata)
    case receivePayment(PaymentMetadata)
}

// MARK: - Errors -

extension IntentMetadata {
    enum Error: Swift.Error {
        case unsupportedMetadataType
    }
}

// MARK: - Proto -

extension IntentMetadata {
    init(_ metadata: Ocp_Transaction_V1_Metadata) throws {
        guard let type = metadata.type else {
            throw Error.unsupportedMetadataType
        }
        
        switch type {
        case .openAccounts:
            self = .openAccounts
            
        case .receivePaymentsPublicly(let meta):
            self = .receivePayment(PaymentMetadata(
                exchangedFiat: try ExchangedFiat(meta.exchangeData)
            ))
            
        case .sendPublicPayment(let meta):
            self = .sendPayment(PaymentMetadata(
                exchangedFiat: try ExchangedFiat(meta.exchangeData)
            ))
        case .publicDistribution(let meta):
            // TODO: Implement
            fatalError("Unimplemented")
        }
    }
}
