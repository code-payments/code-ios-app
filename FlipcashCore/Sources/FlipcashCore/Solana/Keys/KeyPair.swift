//
//  KeyPair.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

public struct KeyPair: Equatable, Codable, Hashable, Sendable {
    
    public let publicKey: PublicKey
    public let privateKey: PrivateKey
    public let seed: Seed32?
    
    /// Some cryptographic function require the private
    /// key to be formatted this way to work correctly.
    /// A good example of this would Sodium and the box
    /// `seal` and `open` functions.
    /// 
    public var encryptionPrivateKey: PrivateKey? {
        guard let seed else {
            return nil
        }
        
        return try? PrivateKey(seed.bytes + publicKey.bytes)
    }
    
    // MARK: - Init -
    
    public static func generate() -> KeyPair? {
        guard let seed = Seed32.generate() else {
            return nil
        }
        
        return KeyPair(seed: seed)
    }
    
    /// Seed derived using BIP39 spec.
    /// Reference: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
    ///
    public init(mnemonic: MnemonicPhrase, path: Derive.Path) {
        self = Derive.keyPairUsingBIP39(
            path: path,
            phrase: mnemonic.words,
            password: path.password ?? ""
        )
    }
    
    public init(publicKey: PublicKey, privateKey: PrivateKey) {
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.seed = nil
    }
    
    public init(seed: Seed32) {
        let pair = SharedEd25519.keyPair(seed: Data(seed.bytes))
        
        self.seed       = seed
        self.publicKey  = try! PublicKey([Byte](pair.publicKey))
        self.privateKey = try! PrivateKey([Byte](pair.privateKey))
    }
    
    // MARK: - Signing -
    
    public func sign(_ data: Data) -> Signature {
        sign(data.bytes)
    }
    
    public func sign(_ bytes: [Byte]) -> Signature {
        let signature = SharedEd25519.sign(
            message: Data(bytes),
            keyPair: SharedEd25519.KeyPair(
                publicKey: Data(publicKey.bytes),
                privateKey: Data(privateKey.bytes)
            )
        )
        
        return try! Signature([Byte](signature))
    }
    
    public func verify(signature: Signature, data: Data) -> Bool {
        publicKey.verify(signature: signature, data: data)
    }

    public func verify(signature: Signature, bytes: [Byte]) -> Bool {
        publicKey.verify(signature: signature, bytes: bytes)
    }
}

// MARK: - PublicKey -

extension PublicKey {
    
    public func isOnCurve() -> Bool {
        SharedEd25519.isOnCurve(publicKey: Data(bytes))
    }
    
    public func verify(signature: Signature, data: Data) -> Bool {
        verify(signature: signature, bytes: data.bytes)
    }
    
    public func verify(signature: Signature, bytes: [Byte]) -> Bool {
        SharedEd25519.verify(
            signature: Data(signature.bytes),
            message: Data(bytes),
            publicKey: Data(self.bytes)
        )
    }
}
