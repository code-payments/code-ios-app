//
//  FlipClient+IAP.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func completePurchase(receipt: Data, productID: String, price: Double, currency: String, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            iapService.completePurchase(receipt: receipt, productID: productID, price: price, currency: currency, owner: owner) { c.resume(with: $0) }
        }
    }
}
