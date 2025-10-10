//
//  Client+Currency.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func fetchExchangeRates() async throws -> RatesSnapshot {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchExchangeRates { c.resume(with: $0) }
        }
    }
    
    public func fetchMint(mint: PublicKey) async throws -> MintMetadata {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchMint(mint: mint) { c.resume(with: $0) }
        }
    }
    
//    public func fetchMints(mints: [PublicKey]) async throws -> [PublicKey: MintMetadata] {
//        try await withCheckedThrowingContinuation { c in
//            currencyService.fetchMints(mints: mints) { c.resume(with: $0) }
//        }
//    }
}
