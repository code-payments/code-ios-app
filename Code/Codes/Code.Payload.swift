//
//  Code.Payload.swift
//  Code
//
//  Created by Dima Bart on 2021-02-02.
//

import Foundation
import CryptoKit

extension Code {
    struct Payload {
        var kind: Kind
        var amount: Decimal
        var nonce: Nonce
    }
}

extension Code.Payload {
    enum Kind: Int {
        case `default`
    }
}

extension Code.Payload {
    enum Nonce {
        
        static let length: Int = 11
        
        case generate
        case custom(Data)
        
        var value: Data {
            switch self {
            case .generate:
                return Data.randomBytes(length: Nonce.length)
                
            case .custom(let data):
                return data
            }
        }
    }
}

extension Data {
    static func randomBytes(length: Int) -> Data {
        var data = Data(capacity: length)
        let result = data.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            SecRandomCopyBytes(kSecRandomDefault, length, pointer.baseAddress!)
        }
        
        if result == errSecSuccess {
            return data
        } else {
            let uuid = UUID().uuid
            return Data([
                uuid.0, uuid.1, uuid.2, uuid.3,
                uuid.4, uuid.5, uuid.6, uuid.7,
                uuid.8, uuid.9, uuid.10,
            ])
        }
    }
}
