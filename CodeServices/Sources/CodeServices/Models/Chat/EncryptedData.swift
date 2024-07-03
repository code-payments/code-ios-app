//
//  EncryptedData.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Clibsodium

public struct EncryptedData: Equatable, Hashable, Codable {
    
    public var peerPublicKey: PublicKey
    public var nonce: Data
    public var encryptedData: Data
    
    public init(peerPublicKey: PublicKey, nonce: Data, encryptedData: Data) {
        self.peerPublicKey = peerPublicKey
        self.nonce = nonce
        self.encryptedData = encryptedData
    }
    
    public func decryptMessageUsingNaclBox(keyPair: KeyPair) throws -> String {
        guard let encryptionKey = keyPair.encryptionPrivateKey else {
            throw Error.invalidKeyPair
        }
        
        let data = try encryptedData.boxOpen(
            privateKey: encryptionKey,
            publicKey: peerPublicKey,
            nonce: nonce
        )
        
        return String(data: data, encoding: .utf8)!
    }
    
    enum Error: Swift.Error {
        case invalidKeyPair
    }
}
