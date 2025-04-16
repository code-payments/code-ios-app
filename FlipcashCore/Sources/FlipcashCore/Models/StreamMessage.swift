//
//  StreamMessage.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation
import FlipcashAPI

public struct StreamMessage: Sendable {
    public enum Kind: Sendable {
        case paymentRequest(PaymentRequest)
        case airdrop(Airdrop)
    }
    
    public let id: ID
    public let kind: Kind
    
    public init(id: ID, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

// MARK: - Errors -

extension StreamMessage {
    enum Error: Swift.Error {
        case failedToParse
        case messageNotSupported
    }
}

// MARK: - Conveniences -

extension StreamMessage {
    
    public var paymentRequest: PaymentRequest? {
        if case .paymentRequest(let request) = kind {
            return request
        } else {
            return nil
        }
    }
    
    public var airdrop: Airdrop? {
        if case .airdrop(let airdrop) = kind {
            return airdrop
        } else {
            return nil
        }
    }
}

// MARK: - Proto -

extension StreamMessage {

    init(_ message: Code_Messaging_V1_Message) throws {
        self.id = ID(data: message.id.value)
        
        switch message.kind {
        case .requestToGrabBill(let request):
            guard
                let account = PublicKey(request.requestorAccount.value),
                let signature = Signature(message.sendMessageRequestSignature.value)
            else {
                throw Error.failedToParse
            }
            
            self.kind = .paymentRequest(
                PaymentRequest(account: account, signature: signature)
            )
            
        case .airdropReceived(let airdrop):
            self.kind = .airdrop(
                Airdrop(
                    type: try AirdropType(airdrop.airdropType),
                    date: airdrop.timestamp.date,
                    exchangedFiat: try ExchangedFiat(airdrop.exchangeData)
                )
            )
            
        default:
            throw Error.messageNotSupported
        }
    }
}
