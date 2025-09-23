//
//  WalletResponse.swift
//  Code
//
//  Created by Dima Bart on 2025-09-17.
//

import Foundation
import FlipcashCore

public protocol WalletResponse {
    init(url: URL) throws
    init(params: [String: String]) throws
}

public struct WalletResponseConnect: WalletResponse {
    
    public let encryptionPublicKey: Data
    public let nonce: Data
    public let data: Data
    
    public init(params: [String : String]) throws {
        guard
            let encryptionPublicKey = params["phantom_encryption_public_key"],
            let nonce               = params["nonce"],
            let data                = params["data"]
        else {
            throw WalletResponseError.invalidURL
        }
        
        self.encryptionPublicKey = Base58.toBytes(encryptionPublicKey).data
        self.nonce               = Base58.toBytes(nonce).data
        self.data                = Base58.toBytes(data).data
    }
}

extension WalletResponse {
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
}

public enum WalletResponseError: Error {
    case invalidURL
}
