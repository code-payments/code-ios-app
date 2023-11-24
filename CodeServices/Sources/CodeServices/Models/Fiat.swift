//
//  Fiat.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Fiat: Equatable, Hashable, Codable {
    
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
}

public enum GenericAmount: Equatable, Hashable {
    
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
