//
//  EncryptedWalletResponse.swift
//  Code
//
//  Created by Dima Bart on 2025-09-17.
//

import Foundation
import FlipcashCore

public struct EncryptedWalletResponse {
    
    public let nonce: Data
    public let data: Data
    
    public var encryptionPublicKey: Data?
    
    public init(url: URL) throws {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WalletResponseError.invalidURL
        }
        
        var params: [String: String] = [:]
        c.queryItems?.forEach {
            if let value = $0.value {
                params[$0.name] = value
            }
        }
        
        try self.init(params: params)
    }
    
    init(params: [String : String]) throws {
        guard
            let nonce = params["nonce"],
            let data  = params["data"]
        else {
            throw WalletResponseError.invalidURL
        }
        
        self.nonce = Base58.toBytes(nonce).data
        self.data  = Base58.toBytes(data).data
        
        if let encryptionPublicKey = params["phantom_encryption_public_key"] {
            self.encryptionPublicKey = Base58.toBytes(encryptionPublicKey).data
        } else {
            self.encryptionPublicKey = nil
        }
    }
}

public enum WalletResponse {}

public enum WalletResponseError: Error {
    case invalidURL
}
