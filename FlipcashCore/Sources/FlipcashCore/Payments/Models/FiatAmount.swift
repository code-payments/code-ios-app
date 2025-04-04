//
//  FiatAmount.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-02.
//

import Foundation

public struct FiatAmount: Equatable, Hashable, Codable, Sendable {
    
    public let fiat: Fiat
    public let rate: Rate
    
    // MARK: - Init -
    
    public init(fiat: Fiat, rate: Rate) {
        self.fiat = fiat
        self.rate = rate
    }

    public init?(stringAmount: String, currency: CurrencyCode, rate: Rate) {
        guard let amount = NumberFormatter.decimal(from: stringAmount), amount > 0 else {
            return nil
        }
        
        guard let fiat = Fiat(fiat: amount, currencyCode: currency) else {
            return nil
        }

        self.init(
            fiat: fiat,
            rate: rate
        )
    }
    
    // MARK: - Rates -
    
    public func replacing(rate: Rate) -> FiatAmount {
        FiatAmount(
            fiat: fiat,
            rate: rate
        )
    }
}
