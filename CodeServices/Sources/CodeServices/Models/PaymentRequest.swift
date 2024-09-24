//
//  PaymentRequest.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public struct StreamMessage: Sendable {
    public enum Kind: Sendable {
        case receiveRequest(ReceiveRequest)
        case paymentRequest(PaymentRequest)
        case loginRequest(LoginRequest)
        case airdrop(Airdrop)
    }
    
    public let id: ID
    public let kind: Kind
    
    public init(id: ID, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

public struct Fee: Equatable, Hashable, Sendable {
    public var destination: PublicKey
    public var bps: Int
}

public struct ReceiveRequest: Sendable {
    
    public enum Amount: Sendable {
        case exact(KinAmount)
        case partial(Fiat)
    }
    
    public let account: PublicKey
    public let signature: Signature
    public let amount: Amount
    
    public let domain: Domain?
    public let verifier: PublicKey?
    
    public let additionalFees: [Fee]
    
    public init(account: PublicKey, signature: Signature, amount: Amount, domain: Domain?, verifier: PublicKey?, additionalFees: [Fee]) {
        self.account = account
        self.signature = signature
        self.amount = amount
        self.domain = domain
        self.verifier = verifier
        self.additionalFees = additionalFees
    }
}

public struct PaymentRequest: Sendable {
    public let account: PublicKey
    public let signature: Signature
    
    public init(account: PublicKey, signature: Signature) {
        self.account = account
        self.signature = signature
    }
}

public struct LoginRequest: Sendable {
    public let domain: Domain
    public let verifier: PublicKey
    public let rendezvous: PublicKey
    public let signature: Signature
    
    public init(domain: Domain, verifier: PublicKey, rendezvous: PublicKey, signature: Signature) {
        self.domain = domain
        self.verifier = verifier
        self.rendezvous = rendezvous
        self.signature = signature
    }
}

public struct Airdrop: Sendable {
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
    
    public var loginRequest: LoginRequest? {
        if case .loginRequest(let loginRequest) = kind {
            return loginRequest
        } else {
            return nil
        }
    }
}

// MARK: - Errors -

extension StreamMessage {
    enum Error: Swift.Error {
        case failedToParse
        case messageNotSupported
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
            
        case .requestToReceiveBill(let request):
            guard
                let exchangeData = request.exchangeData,
                let account = PublicKey(request.requestorAccount.value),
                let signature = Signature(message.sendMessageRequestSignature.value)
            else {
                throw Error.failedToParse
            }
            
            let additionalFees = try request.additionalFees.compactMap {
                guard let destination = PublicKey($0.destination.value) else {
                    throw Error.failedToParse
                }
                
                return Fee(
                    destination: destination,
                    bps: Int($0.feeBps)
                )
            }
            
            let domain: Domain?
            let verifier: PublicKey?
            
            if request.hasDomain {
                guard 
                    let validDomain = Domain(request.domain.value),
                    let validVerifier = PublicKey(request.verifier.value)
                else {
                    throw Error.failedToParse
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
                    throw Error.failedToParse
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
                        verifier: verifier,
                        additionalFees: additionalFees
                    )
                )
                
            case .partial(let exchangeData):
                guard let currency = CurrencyCode(currencyCode: exchangeData.currency) else {
                    throw Error.failedToParse
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
                        verifier: verifier,
                        additionalFees: additionalFees
                    )
                )
            }
            
        case .airdropReceived(let airdrop):
            guard
                let type = AirdropType(airdrop.airdropType),
                let currency = CurrencyCode(currencyCode: airdrop.exchangeData.currency)
            else {
                throw Error.failedToParse
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
            
        case .requestToLogin(let loginRequest):
            guard
                let domain = Domain(loginRequest.domain.value),
                let verifier = PublicKey(loginRequest.verifier.value),
                let rendezvous = PublicKey(loginRequest.rendezvousKey.value),
                let signature = Signature(loginRequest.signature.value)
            else {
                throw Error.failedToParse
            }
            
            self.kind = .loginRequest(
                LoginRequest(
                    domain: domain,
                    verifier: verifier,
                    rendezvous: rendezvous,
                    signature: signature
                )
            )
            
        default:
            throw Error.messageNotSupported
        }
    }
}
