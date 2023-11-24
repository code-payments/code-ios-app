//
//  Derive.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public typealias KeyDescriptor = (key: Data, chain: Data)

/// Deterministic wallet generation for ED25519 curve using SLIP-0010 spec
/// Reference: https://github.com/satoshilabs/slips/blob/master/slip-0010.md
///
public enum Derive {
    
    private static let curve: Data = Data("ed25519 seed".utf8)
    private static let hardenedOffset: UInt32 = 0x80000000
    
    static func masterKey(seed: Data) -> KeyDescriptor {
        seed.hmac(using: curve).split32()
    }
    
    static func path(path: Path, seed: Data) -> (keyPair: KeyPair, chaincode: Data) {
        var descriptor = masterKey(seed: seed)
        
        path.indexes.forEach { index in
            descriptor = CKDPriv(keyDescriptor: descriptor, index: hardenedOffset + index.value)
        }
        
        return (
            KeyPair(seed: Seed32(descriptor.key)!),
            descriptor.chain
        )
    }
    
    private static func CKDPriv(keyDescriptor: KeyDescriptor, index: UInt32) -> KeyDescriptor {
        var entropy = Data()
        entropy.append(0x00)
        entropy.append(keyDescriptor.key)
        entropy.append(contentsOf: index.bigEndian.bytes)
        
        return entropy.hmac(using: keyDescriptor.chain).split32()
    }
}

/// Deterministic key derivation using BIP39
/// Reference: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
///
extension Derive {
    
    static func seedUsingBIP39(phrase: [String], password: String = "") -> Key64 {
        let phrase = phrase.joined(separator: " ")
        let salt = "mnemonic\(password)"
        
        let bytes = PBKDF.deriveKey(
            algorithm: .sha512,
            password: phrase,
            salt: salt
        )
        
        return Key64(bytes)!
    }
    
    public static func keyPairUsingBIP39(path: Path, phrase: [String], password: String = "") -> KeyPair {
        let key64 = seedUsingBIP39(
            phrase: phrase,
            password: password
        )
        
        return Derive.path(path: path, seed: key64.data).keyPair
    }
}

// MARK: - Data -

private extension Data {
    
    func split32() -> (Data, Data) {
        let lhs = Data(self[0..<32])
        let rhs = Data(self[32..<64])
        return (lhs, rhs)
    }
    
    func hmac(using key: Data) -> Data {
        var hmac = HMAC(algorithm: .sha512, key: key)
        hmac.update(self)
        return hmac.digestData()
    }
}
