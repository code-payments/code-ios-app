//
//  Rate.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Rate: Codable, Equatable, Hashable, Sendable {
    
    public var fx: Decimal
    public var currency: CurrencyCode
    
    public init(fx: Decimal, currency: CurrencyCode) {
        self.fx = fx
        self.currency = currency
    }
    
    public init?(fx: Decimal, currencyCode: String) {
        guard let currency = CurrencyCode(currencyCode: currencyCode) else {
            return nil
        }
        
        self.init(fx: fx, currency: currency)
    }
}

extension Rate {
    public static let oneToOne = Rate(fx: 1, currency: .usd)
}
