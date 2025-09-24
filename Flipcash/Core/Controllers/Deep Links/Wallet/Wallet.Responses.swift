//
//  Responses.swift
//  Code
//
//  Created by Dima Bart on 2025-09-23.
//

import Foundation

extension WalletResponse {
    public struct Connected: Decodable {
        
        public let publicKey: String
        public let session: String
        
        enum CodingKeys: String, CodingKey {
            case publicKey = "public_key"
            case session
        }
    }
}

extension WalletResponse {
    public struct SignedTransactions: Decodable {
        public let transactions: [String]
    }
}
