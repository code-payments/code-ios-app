//
//  Chat.Content.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

extension Chat {
    public enum Content: Equatable, Hashable, Sendable {
        case text(String)
        case localized(String)
        case kin(GenericAmount, Verb, Reference)
        case sodiumBox(EncryptedData)
        case thankYou(PublicKey) // IntentID
        case identityRevealed(MemberID, Chat.Member.Identity)
        case identity(Direction, Chat.Member.Identity)
    }
}

extension Chat.Content {
    public enum Direction: Sendable {
        case fromSelf
        case fromOther
    }
}

// MARK: - Proto -

extension Chat.Content {
    
    var codeContent: Code_Chat_V2_Content {
        switch self {
        case .text(let string):
            return .with {
                $0.text = .with {
                    $0.text = string
                }
            }
            
        case .thankYou(let publicKey):
            return .with {
                $0.thankYou = .with {
                    $0.tipIntent = publicKey.codeIntentID
                }
            }
            
        case .identityRevealed(let memberID, let identity):
            return .with {
                $0.identityRevealed = .with {
                    $0.memberID = .with { $0.value = memberID.data }
                    $0.identity = identity.codeIdentity
                }
            }
            
        case .localized, .kin, .sodiumBox, .identity:
            fatalError("Content unsupported")
        }
    }
    
    public init?(_ proto: Code_Chat_V2_Content) {
        guard let type = proto.type else {
            return nil
        }
        
        switch type {
        case .text(let content):
            self = .text(content.text)
            
        case .localized(let string):
            self = .localized(string.keyOrText)
            
        case .exchangeData(let exchange):
            
            guard let reference = Chat.Reference(exchange.reference) else {
                return nil
            }
            
            let verb: Chat.Verb
            
            switch exchange.verb {
            case .unknown:
                verb = .unknown
            case .gave:
                verb = .gave
            case .received:
                verb = .received
            case .withdrew:
                verb = .withdrew
            case .deposited:
                verb = .deposited
            case .sent:
                verb = .sent
            case .returned:
                verb = .returned
            case .spent:
                verb = .spent
            case .paid:
                verb = .paid
            case .purchased:
                verb = .purchased
            case .receivedTip:
                verb = .tipReceived
            case .sentTip:
                verb = .tipSent
            case .UNRECOGNIZED:
                verb = .unknown
            }
            
            let amount: KinAmount
            
            switch exchange.exchangeData {
            case .exact(let exact):
                guard let currency = CurrencyCode(currencyCode: exact.currency) else {
                    return nil
                }
                
                amount = KinAmount(
                    kin: Kin(quarks: exact.quarks),
                    rate: Rate(
                        fx: Decimal(exact.exchangeRate),
                        currency: currency
                    )
                )
                
                self = .kin(.exact(amount), verb, reference)
                
            case .partial(let partial):
                guard let currency = CurrencyCode(currencyCode: partial.currency) else {
                    return nil
                }
                
                let fiat = Fiat(
                    currency: currency,
                    amount: partial.nativeAmount
                )
                
                self = .kin(.partial(fiat), verb, reference)
                
            case .none:
                return nil
            }
            
            
        case .naclBox(let encryptedContent):
            guard let peerPublicKey = PublicKey(encryptedContent.peerPublicKey.value) else {
                return nil
            }
            
            let data = EncryptedData(
                peerPublicKey: peerPublicKey,
                nonce: encryptedContent.nonce,
                encryptedData: encryptedContent.encryptedPayload
            )
            
            self = .sodiumBox(data)
            
        case .identityRevealed(let content):
            
            let memberID = MemberID(data: content.memberID.value)
            let identity = Chat.Member.Identity(content.identity)
            
            self = .identityRevealed(memberID, identity)
        
        case .thankYou(let content):
            guard let intentID = PublicKey(content.tipIntent.value) else {
                return nil
            }
            
            self = .thankYou(intentID)
        }
    }
}

extension Chat.Member.Identity {
    var codeIdentity: Code_Chat_V2_ChatMemberIdentity {
        switch self {
        case .unknown(let username):
            return .with {
                $0.platform = .unknownPlatform
                $0.username = username
            }
            
        case .twitter(let username, _):
            return .with {
                $0.platform = .twitter
                $0.username = username
            }
        }
    }
}
