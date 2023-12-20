//
//  PaymentRequest.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public struct StreamMessage {
    public enum Kind {
        case receiveRequest(ReceiveRequest)
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

public struct ReceiveRequest {
    
    public enum Amount {
        case exact(KinAmount)
        case partial(Fiat)
    }
    
    public let account: PublicKey
    public let signature: Signature
    public let amount: Amount
    
    public let domain: Domain?
    public let verifier: PublicKey?
    
    public init(account: PublicKey, signature: Signature, amount: Amount, domain: Domain?, verifier: PublicKey?) {
        self.account = account
        self.signature = signature
        self.amount = amount
        self.domain = domain
        self.verifier = verifier
    }
}

public struct PaymentRequest {
    public let account: PublicKey
    public let signature: Signature
    
    public init(account: PublicKey, signature: Signature) {
        self.account = account
        self.signature = signature
    }
}

public struct Airdrop {
    public let type: AirdropType
    public let date: Date
    public let kinAmount: KinAmount
    
    public init(type: AirdropType, date: Date, kinAmount: KinAmount) {
        self.type = type
        self.date = date
        self.kinAmount = kinAmount
    }
}

// MARK: - Utilities -

extension StreamMessage {
    public var receiveRequest: ReceiveRequest? {
        if case .receiveRequest(let request) = kind {
            return request
        } else {
            return nil
        }
    }
    
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

    init?(_ message: Code_Messaging_V1_Message) {
        self.id = ID(data: message.id.value)
        
        switch message.kind {
        case .requestToGrabBill(let request):
            guard
                let account = PublicKey(request.requestorAccount.value),
                let signature = Signature(message.sendMessageRequestSignature.value)
            else {
                return nil
            }
            
            self.kind = .paymentRequest(
                PaymentRequest(account: account, signature: signature)
            )
            
        case .requestToReceiveBill(let request):
            guard
                let exchangeData = request.exchangeData,
                let account = PublicKey(request.requestorAccount.value),
                let signature = Signature(message.sendMessageRequestSignature.value)
            else {
                return nil
            }
            
            let domain: Domain?
            let verifier: PublicKey?
            
            if request.hasDomain {
                guard 
                    let validDomain = Domain(request.domain.value),
                    let validVerifier = PublicKey(request.verifier.value)
                else {
                    return nil
                }
                
                domain = validDomain
                verifier = validVerifier
                
            } else {
                domain = nil
                verifier = nil
            }
            
            switch exchangeData {
            case .exact(let exchangeData):
                guard let currency = CurrencyCode(currencyCode: exchangeData.currency) else {
                    return nil
                }
                
                self.kind = .receiveRequest(
                    ReceiveRequest(
                        account: account,
                        signature: signature,
                        amount: .exact(
                            KinAmount(
                                kin: Kin(quarks: exchangeData.quarks),
                                rate: Rate(
                                    fx: Decimal(exchangeData.exchangeRate),
                                    currency: currency
                                )
                            )
                        ),
                        domain: domain,
                        verifier: verifier
                    )
                )
                
            case .partial(let exchangeData):
                guard let currency = CurrencyCode(currencyCode: exchangeData.currency) else {
                    return nil
                }
                
                self.kind = .receiveRequest(
                    ReceiveRequest(
                        account: account,
                        signature: signature,
                        amount: .partial(
                            Fiat(
                                currency: currency,
                                amount: exchangeData.nativeAmount
                            )
                        ),
                        domain: domain,
                        verifier: verifier
                    )
                )
            }
            
        case .airdropReceived(let airdrop):
            guard
                let type = AirdropType(airdrop.airdropType),
                let currency = CurrencyCode(currencyCode: airdrop.exchangeData.currency)
            else {
                return nil
            }
            
            self.kind = .airdrop(
                Airdrop(
                    type: type,
                    date: airdrop.timestamp.date,
                    kinAmount: KinAmount(
                        kin: Kin(quarks: airdrop.exchangeData.quarks),
                        rate: Rate(
                            fx: Decimal(airdrop.exchangeData.exchangeRate),
                            currency: currency
                        )
                    )
                )
            )
            
        default:
            return nil
        }
    }
}
