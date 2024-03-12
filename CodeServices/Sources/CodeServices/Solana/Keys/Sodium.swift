//
//  Sodium.swift
//  
//
//  Created by Dima Bart on 2024-03-06.
//

import Foundation
import Clibsodium
import Sodium

// Even though we won't use this instance directly,
// it initializes the underlying libsodium library
//private let sodium = Sodium()

extension KeyType {
    
    public var curvePrivate: PublicKey? {
        var localBytes = bytes
        var curve = [Byte](repeating: 0, count: 32)
        
        let result = crypto_sign_ed25519_sk_to_curve25519(&curve, &localBytes)
        if result == 0 {
            return PublicKey(curve)
        } else {
            return nil
        }
    }
    
    public var curvePublic: PublicKey? {
        var localBytes = bytes
        var curve = [Byte](repeating: 0, count: 32)
        
        let result = crypto_sign_ed25519_pk_to_curve25519(&curve, &localBytes)
        if result == 0 {
            return PublicKey(curve)
        } else {
            return nil
        }
    }
    
    public static func shared(publicKey: PublicKey, privateKey: PublicKey) -> PublicKey? {
        var shared = [Byte](repeating: 0, count: 32)
        let r = crypto_box_curve25519xsalsa20poly1305_beforenm(
            &shared,
            publicKey.bytes,
            privateKey.bytes
        )
        
        guard r == 0 else {
            return nil
        }
        
        return PublicKey(shared)
    }
}

extension Data {
    
    public enum SodiumError: Error {
        case conversionToCurveFailed
        case sharedKeyFailed
        case encryptionFailed
        case decryptionFailed
    }
    
    public func boxSeal(privateKey: PrivateKey, publicKey: PublicKey, nonce: Data) throws -> Data {
        _ = Sodium() // Initialize sodium
        
        guard
            let publicCurve  = publicKey.curvePublic,
            let privateCurve = privateKey.curvePrivate
        else {
            throw SodiumError.conversionToCurveFailed
        }
        
        // 1. Establish a shared key between
        // the sender and the receiver
        let sharedKey = PublicKey.shared(
            publicKey: publicCurve,
            privateKey: privateCurve
        )
        
        guard let sharedKey else {
            throw SodiumError.sharedKeyFailed
        }
        
        // 2. Encrypt the message
        
        let nonce  = nonce.bytes
        let message = self.bytes
        
        var encrypted = [Byte](repeating: 0, count: message.count + Int(crypto_box_macbytes()))
        
        let result = crypto_secretbox_easy(
            &encrypted,            // unsigned char *m
            message,               // const unsigned char *m
            UInt64(message.count), // unsigned long long mlen
            nonce,                 // const unsigned char *n (24 bytes)
            sharedKey.bytes        // const unsigned char *s (32 bytes)
        )
        
        guard result == 0 else {
            throw SodiumError.encryptionFailed
        }
        
        return Data(encrypted)
    }
    
    public func boxOpen(privateKey: PrivateKey, publicKey: PublicKey, nonce: Data) throws -> Data {
        _ = Sodium() // Initialize sodium
        
        guard
            let publicCurve  = publicKey.curvePublic,
            let privateCurve = privateKey.curvePrivate
        else {
            throw SodiumError.conversionToCurveFailed
        }
        
        // 1. Establish a shared key between
        // the sender and the receiver
        let sharedKey = PublicKey.shared(
            publicKey: publicCurve,
            privateKey: privateCurve
        )
        
        guard let sharedKey else {
            throw SodiumError.sharedKeyFailed
        }
        
        // 2. Decrypt the message
        
        let nonce  = nonce.bytes
        let cipher = self.bytes
        
        var decrypted = [Byte](repeating: 0, count: cipher.count - Int(crypto_box_macbytes()))
        
        let result = crypto_secretbox_open_easy(
            &decrypted,           // unsigned char *m
            cipher,               // const unsigned char *c
            UInt64(cipher.count), // unsigned long long clen
            nonce,                // const unsigned char *n (24 bytes)
            sharedKey.bytes       // const unsigned char *s (32 bytes)
        )
        
        guard result == 0 else {
            throw SodiumError.decryptionFailed
        }
        
        return Data(decrypted)
    }
}
