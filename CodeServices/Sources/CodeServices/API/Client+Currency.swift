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
    
    public func fetchExchangeRateHistory(range: DateRange, interval: DateRange.Interval) async throws -> [Rate] {
        try await withCheckedThrowingContinuation { c in
            currencyService.fetchExchangeRateHistory(range: range, interval: interval) { c.resume(with: $0) }
        }
    }
}
