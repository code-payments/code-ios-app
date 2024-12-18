//
//  FlipchatClient+Purchase.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension FlipchatClient {
    
    public func notifyPurchaseCompleted(receipt: Data, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            purchaseService.notifyPurchaseCompleted(receipt: receipt, owner: owner) { c.resume(with: $0) }
        }
    }
}
