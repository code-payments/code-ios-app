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
            // Handle oneof exchange_data - server returns serverExchangeData for submitted intents
            switch meta.exchangeData {
            case .serverExchangeData(let serverData):
                self = .sendPayment(PaymentMetadata(
                    exchangedFiat: try ExchangedFiat(serverData)
                ))
            case .clientExchangeData, .none:
                // clientExchangeData is what clients send, not what server returns
                throw Error.unsupportedMetadataType
            }

        case .sendPublicMultiPayment:
            // Multi-payment intents are only issued for reaction boosts, which the app does not
            // surface as a payment through the intent metadata poll.
            throw Error.unsupportedMetadataType

        case .publicDistribution:
            throw Error.unsupportedMetadataType
        }
    }
}
