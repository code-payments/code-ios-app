//
//  KeyPair.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import ed25519

public struct KeyPair: Equatable, Codable, Hashable {
    
    public let publicKey: PublicKey
    public let privateKey: PrivateKey
    public let seed: Seed32?
    
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
    public init(mnemonic: MnemonicPhrase, path: Derive.Path, password: String? = nil) {
        self = Derive.keyPairUsingBIP39(
            path: path,
            phrase: mnemonic.words,
            password: password ?? ""
        )
    }
    
    public init(publicKey: PublicKey, privateKey: PrivateKey) {
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.seed = nil
    }
    
    public init(seed: Seed32) {
        var publicBytes  = [Byte].zeroed(with: PublicKey.length)
        var privateBytes = [Byte].zeroed(with: PrivateKey.length)
        
        privateBytes.withUnsafeMutableBufferPointer { `private` in
            publicBytes.withUnsafeMutableBufferPointer { `public` in
                seed.bytes.withUnsafeBufferPointer { seed in
                    ed25519_create_keypair(
                        `public`.baseAddress,
                        `private`.baseAddress,
                        seed.baseAddress
                    )
                }
            }
        }
        
        self.seed = seed
        self.publicKey = PublicKey(publicBytes)!
        self.privateKey = PrivateKey(privateBytes)!
    }
    
    // MARK: - Signing -
    
    public func sign(_ data: Data) -> Signature {
        sign(data.bytes)
    }
    
    public func sign(_ bytes: [Byte]) -> Signature {
        var signData = [Byte].zeroed(with: Signature.length)
        
        signData.withUnsafeMutableBufferPointer { signature in
            privateKey.bytes.withUnsafeBufferPointer { `private` in
                publicKey.bytes.withUnsafeBufferPointer { `public` in
                    bytes.withUnsafeBufferPointer { msg in
                        ed25519_sign(
                            signature.baseAddress,
                            msg.baseAddress,
                            bytes.count,
                            `public`.baseAddress,
                            `private`.baseAddress
                        )
                    }
                }
            }
        }
        
        return Signature(signData)!
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
        bytes.withUnsafeBufferPointer {
            ed25519_on_curve($0.baseAddress) == 1
        }
    }
    
    public func verify(signature: Signature, data: Data) -> Bool {
        verify(signature: signature, bytes: data.bytes)
    }
    
    public func verify(signature: Signature, bytes: [Byte]) -> Bool {
        signature.bytes.withUnsafeBufferPointer { signature in
            bytes.withUnsafeBufferPointer { message in
                self.bytes.withUnsafeBufferPointer { `public` in
                    ed25519_verify(
                        signature.baseAddress,
                        message.baseAddress,
                        message.count,
                        `public`.baseAddress
                    ) == 1
                }
            }
        }
    }
}
