//
//  Client+Currency.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Client {
    
    public func fetchExchangeRates() async throws -> ([Rate], Date) {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchExchangeRates { c.resume(with: $0) }
        }
    }
}
