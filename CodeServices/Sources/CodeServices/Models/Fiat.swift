//
//  Fiat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Fiat: Equatable, Hashable, Codable, Sendable {
    
    public let currency: CurrencyCode
    public let amount: Decimal
    
    // MARK: - Init -
    
    public init(currency: CurrencyCode, amount: Decimal) {
        self.currency = currency
        self.amount = amount
    }
    
    public init(currency: CurrencyCode, amount: Double) {
        self.init(
            currency: currency,
            amount: Decimal(amount)
        )
    }
    
    public init?(currency: CurrencyCode, stringAmount: String) {
        guard let amount = NumberFormatter.decimal(from: stringAmount), amount > 0 else {
            return nil
        }

        self.init(currency: currency, amount: amount)
    }
}

extension Fiat {
    public static let zero = Fiat(currency: .usd, amount: Decimal(0))
}

public enum GenericAmount: Equatable, Hashable, Sendable {
    
    case exact(KinAmount)
    case partial(Fiat)
    
    public var currency: CurrencyCode {
        switch self {
        case .exact(let amount):
            return amount.rate.currency
            
        case .partial(let fiat):
            return fiat.currency
        }
    }
    
    public func amountUsing(rate: Rate) -> KinAmount {
        switch self {
        case .exact(let amount):
            return amount
            
        case .partial(let fiat):
            return KinAmount(
                fiat: fiat.amount,
                rate: rate
            )
        }
    }
}
