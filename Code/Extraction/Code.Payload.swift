//
//  Code.Payload.swift
//  Code
//
//  Created by Dima Bart on 2021-02-02.
//

import Foundation
import CodeServices

extension Code {
    struct Payload: Equatable {
        
        let kind: Kind
        let value: Value
        let nonce: Data
        
        let rendezvous: KeyPair
        
        init(kind: Kind, kin: Kin, nonce: Data) {
            self.init(
                kind: kind,
                value: .kin(kin),
                nonce: nonce
            )
        }
        
        init(kind: Kind, fiat: Fiat, nonce: Data) {
            self.init(
                kind: kind,
                value: .fiat(fiat),
                nonce: nonce
            )
        }
        
        init(kind: Kind, value: Value, nonce: Data) {
            self.kind = kind
            self.value = value
            self.nonce = nonce
            
            switch value {
            case .kin(let kin):
                self.rendezvous = KeyPair.deriveRendezvousKey(from: Self.encode(kind: kind, kin: kin, nonce: nonce))
            case .fiat(let fiat):
                self.rendezvous = KeyPair.deriveRendezvousKey(from: Self.encode(kind: kind, fiat: fiat, nonce: nonce))
            }
        }
        
        var kin: Kin? {
            if case .kin(let kin) = value {
                return kin
            }
            return nil
        }
        
        var fiat: Fiat? {
            if case .fiat(let fiat) = value {
                return fiat
            }
            return nil
        }
    }
}

// MARK: - Value -

extension Code.Payload {
    enum Value: Equatable {
        case kin(Kin)
        case fiat(Fiat)
    }
}

// MARK: - Kind -

extension Code.Payload {
    enum Kind: UInt8 {
        case cash           = 0
        case giftCard       = 1
        case requestPayment = 2
    }
}
