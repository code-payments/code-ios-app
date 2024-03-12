//
//  SodiumTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices
import Clibsodium

class SodiumTests: XCTestCase {
    
    let ownerKeyPair = KeyPair(seed: Seed32(base58: "BAjtXtzJzjMvF1qHicCQdyi4AC2y9tQMjVCSwNAY5jnz")!)
    let peerKeyPair  = KeyPair(seed: Seed32(base58: "BWUXLs1epmgQwc6kf3VuWcX4bkwjiRjGDp3CYNcVDpVd")!)
    
    func testPrivateToCurve() {
        let privateKey = PrivateKey(base58: "4vXZTu7W8FKV2cNB7t2MTp8KXrWpJRCodzUPoyPy1MWZiZQqVVXUrycCdoagzPN6YE9w9pyTbZVzVw9iLDUT7adR")!
        XCTAssertEqual(privateKey.curvePrivate?.base58, "F197LA9gxNFgu6bwmHFuBJWU4yuA3wRsBDky9twjeoJr")
    }
    
    func testPublicToCurve() {
        let publicKey = PublicKey(base58: "GV6Aow3jPRXFQiC36EGc1BabhFVY1mEwKPEuwZorGh3R")!
        XCTAssertEqual(publicKey.curvePublic?.base58, "37asXhXd7c8vUNCxHHxAMMrAGPCpYrAtJ8L1fvu4rxzU")
    }
    
    func testSharedKey() {
        let privateKey1 = PrivateKey(base58: "2fJLfaTREkNBiDbB26dL4syDozhCEf2pNMorXvBf7593yC59d1kDFsXAA9cN63Bb5MDUgSeU5AhsfS2aTZQHoNyU")!
        let privateKey2 = PrivateKey(base58: "3GKRCGo814rSVa6XkFARZGq13Rb7DSGwF2c6SSRSzMfyQ3wuDAPoELzhsvH6r5A1PFACpFuesDaRHUEoL1PFAxRa")!
        
        let publicKey1 = PublicKey(base58: "eMTkrsg1acVKyk8jp4b6JQM3TK2fSxwaZV3gZqCmxsp")!
        let publicKey2 = PublicKey(base58: "J1uvrtrg42Yw3zA7v7VK1wBahW8XkTLxqsnKksZab9wS")!
        
        let privateCurve1 = privateKey1.curvePrivate!
        let privateCurve2 = privateKey2.curvePrivate!
     
        let publicCurve1 = publicKey1.curvePublic!
        let publicCurve2 = publicKey2.curvePublic!
        
        let shared1 = PublicKey.shared(
            publicKey: publicCurve1,
            privateKey: privateCurve2
        )!
        
        XCTAssertEqual(shared1.base58, "GC1cihUsj3rBqqdzBmWkEejWuv6p3scxPqCEwUBUUdQq")
        
        let shared2 = PublicKey.shared(
            publicKey: publicCurve2,
            privateKey: privateCurve1
        )!
        
        XCTAssertEqual(shared2.base58, "GC1cihUsj3rBqqdzBmWkEejWuv6p3scxPqCEwUBUUdQq")
    }
    
    func testRoundtrip() throws {
        let senderPrivate = PrivateKey(base58: "2tKSW5f1dag1pGzDSsM9yo32KSMNcTkBAvXEfZ1u2pcqkmo8oYcbtsnA8m9YVd8EUzVJeU5mvjFKjPQF2m4Xifg8")!
        let senderPublic  = PublicKey(base58: "3hpSY5ibVa87dDLJhLdVAy7QVso2Edhr28ZEJmpDF7UQ")!
        
        let receiverPrivate = PrivateKey(base58: "38EyWg6Eay5bhcZR465FD2agT2bf7BhyWNJJ64ypfdQGTb6mHU3an2f8pvWapSrE3j3hEFu1h7HYoa6eykAHUBJr")!
        let receiverPublic  = PublicKey(base58: "6Hsb5k8UjjsowqXgRBr1BR3EKFPeYjA8Nn9prYDU24v6")!
        
        let nonce = Data(Base58.toBytes("Jc1X8GdaMmcRDRKiAaMZSRBDLZAFuf9xq"))
        let expectedEncrypted = Data(Base58.toBytes("2eXsYDo1gcuYc1Nw7uUGZmJZrj2vu33TnrXve62HwzhyTggjjz"))
        
        let message = "super secret message"
        
        let encrypted = try Data(message.utf8).boxSeal(
            privateKey: senderPrivate,
            publicKey: receiverPublic,
            nonce: nonce
        )
        
        XCTAssertEqual(encrypted, expectedEncrypted)
        
        let decrypted = try encrypted.boxOpen(
            privateKey: receiverPrivate,
            publicKey: senderPublic,
            nonce: nonce
        )
        
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), message)
    }
    
    func testRoundtrip2() throws {
        
        let sender   = KeyPair(seed: Seed32(base58: "BAjtXtzJzjMvF1qHicCQdyi4AC2y9tQMjVCSwNAY5jnz")!)
        let receiver = KeyPair(seed: Seed32(base58: "BWUXLs1epmgQwc6kf3VuWcX4bkwjiRjGDp3CYNcVDpVd")!)
        
        let nonce = Data(Base58.toBytes("Jc1X8GdaMmcRDRKiAaMZSRBDLZAFuf9xq"))
        let expectedEncrypted = Data(Base58.toBytes("SZa3RhUVBNhuCT8ARoG5k7V7Ji6TtoJfX8JtpZEHyUzMe4EEb"))
        
        let message = "super secret message"
        
        let encrypted = try Data(message.utf8).boxSeal(
            privateKey: sender.encryptionPrivateKey!,
            publicKey: receiver.publicKey,
            nonce: nonce
        )
        
        XCTAssertEqual(encrypted, expectedEncrypted)
        
        let decrypted = try encrypted.boxOpen(
            privateKey: receiver.encryptionPrivateKey!,
            publicKey: sender.publicKey,
            nonce: nonce
        )
        
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), message)
    }
    
    func testDecryptRealBlockchainMessage() throws {
        let senderPublic = PublicKey(base58: "McS32C1q6Rv1odkEoR5g1xtFBN7TdbkLFvGeyvQtzLF")!
        let receiverKeyPair = KeyPair(seed: Seed32(base58: "CADTR1JPf4KzQ9fuYJMRaaWbfshB8qSb38RpFzC8mtjq")!)
        
//        let senderPrivate = PrivateKey(base58: "3Jf1WGPZ32PJL53nmpA8hQwDGTGy9pGhVoYwYLeS2nBKDPk9PyifujJdQFEZo3b3UzkGU2ACjx3Sk6KbrmY7sKNF")!
        
        let nonce = Data(Base58.toBytes("PjgJtLTPZmHGCqJ6Sj1X4ZN8wVbinW4nU"))
        let encrypted = Data(Base58.toBytes("2BRs8n3fqqDUXVjEdup3d5zoxFALbvs6KcKnMCgpoJ6iafXjikwqbjnbehyha"))
        
        let expectedDecrypted = "Blockchain messaging is 🔥"
        let decrypted = try encrypted.boxOpen(
            privateKey: receiverKeyPair.encryptionPrivateKey!,
            publicKey: senderPublic,
            nonce: nonce
        )
        
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), expectedDecrypted)
    }
}

/*

 Sender private:
 "5e4589807fe3eb4e1a57fa007a4d82d0aba1dc131b4fd4023053f23807d2bf43282c3f423bc134b5e8264c545b57cab2f1cb429b895cd349a88142526d2e7edd"
                                                                 ^ public key start
 Sender public:
 "282c3f423bc134b5e8264c545b57cab2f1cb429b895cd349a88142526d2e7edd"

 Reciever private:
 "78cb6e397efd73df0423749c2e6f0cb74367503cc5ce4b18aa05c4d5f9397c4f024b0e8066453fad570f55bfab3301e550ffe66aee3b9a1c3bb282f59f28e40b"

 Receiver public:
 "72ef6fa149b22fad47898680d0817613db23c6f7601b82a230dd466caffbcde5"
 
*/
