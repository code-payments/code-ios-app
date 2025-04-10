//
//  StreamMessage+Metadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation

public struct PaymentRequest: Sendable {
    public let account: PublicKey
    public let signature: Signature
    
    public init(account: PublicKey, signature: Signature) {
        self.account = account
        self.signature = signature
    }
}
