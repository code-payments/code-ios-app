//
//  FlipClient+IAP.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

extension FlipClient {
    
    public func completePurchase(owner: KeyPair, productID: String, receipt: Data, fiatPaid: Fiat) async throws {
        try await withCheckedThrowingContinuation { c in
            iapService.completePurchase(receipt: receipt, productID: productID, fiatPaid: fiatPaid, owner: owner) { c.resume(with: $0) }
        }
    }
}
