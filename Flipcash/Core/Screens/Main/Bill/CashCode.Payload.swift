//
//  Code.Payload.swift
//  Code
//
//  Created by Dima Bart on 2021-02-02.
//

import Foundation
import FlipcashCore

enum CashCode {}

extension CashCode {
    struct Payload: Equatable {
        
        let kind: Kind
        let value: Value
        let nonce: Data
        
        let rendezvous: KeyPair
        
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
            case .fiat(let fiat):
                self.rendezvous = KeyPair.deriveRendezvousKey(from: Self.encode(kind: kind, fiat: fiat, nonce: nonce))
            }
        }
        
        var fiat: Fiat {
            switch value {
            case .fiat(let fiat):
                return fiat
            }
        }
    }
}

// MARK: - Value -

extension CashCode.Payload {
    enum Value: Equatable {
        case fiat(Fiat)
    }
}

// MARK: - Kind -

extension CashCode.Payload {
    enum Kind: UInt8 {
        case cash = 0
    }
}

extension Data {
    
    static let nonceLength: Int = 10
    
    static var nonce: Data {
        do {
            return try secRandom(nonceLength)
        } catch {
            let uuid = UUID().uuid
            return Data([
                uuid.0, uuid.1, uuid.2, uuid.3, uuid.4,
                uuid.5, uuid.6, uuid.7, uuid.8, uuid.9,
            ])
        }
    }
    
    static func secRandom(_ byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        let result = data.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, pointer.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw Error.randomBytesUnavailable
        }
        
        return data
    }
}

extension Data {
    enum Error: Swift.Error {
        case randomBytesUnavailable
    }
}
