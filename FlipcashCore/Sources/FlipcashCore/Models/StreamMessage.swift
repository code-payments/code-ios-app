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
        case requestToGiveBill(PublicKey, Ocp_Transaction_V1_VerifiedExchangeData?)
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

    public var giveVerifiedState: VerifiedState? {
        guard case .requestToGiveBill(_, let exchangeData) = kind,
              let exchangeData else { return nil }
        return VerifiedState(
            rateProto: exchangeData.coreMintFiatExchangeRate,
            reserveProto: exchangeData.hasLaunchpadCurrencyReserveState ? exchangeData.launchpadCurrencyReserveState : nil
        )
    }
}

// MARK: - Proto -

extension StreamMessage {

    init(_ message: Ocp_Messaging_V1_Message) throws {
        self.id = ID(data: message.id.value)
        
        switch message.kind {
        case .requestToGrabBill(let request):
            self.kind = .paymentRequest(
                PaymentRequest(
                    account: try PublicKey(request.requestorAccount.value),
                    signature: try Signature(message.sendMessageRequestSignature.value)
                )
            )
            
        case .requestToGiveBill(let request):
            let mint = try PublicKey(request.mint.value)
            let exchangeData = request.hasExchangeData ? request.exchangeData : nil
            self.kind = .requestToGiveBill(mint, exchangeData)
            
        default:
            throw Error.messageNotSupported
        }
    }
}
