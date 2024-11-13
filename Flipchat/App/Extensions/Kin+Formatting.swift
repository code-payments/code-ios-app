//
//  Kin+Formatting.swift
//  Code
//
//  Created by Dima Bart on 2022-03-10.
//

import Foundation
import FlipchatServices

extension Kin {
    
    public func formattedFiat(rate: Rate, truncated: Bool = false, showOfKin: Bool) -> String {
        formattedFiat(fx: rate.fx, currency: rate.currency, truncated: truncated, showOfKin: showOfKin)
    }
        
    public func formattedFiat(fx: Decimal, currency: CurrencyCode, truncated: Bool = false, showOfKin: Bool) -> String {
        formattedFiat(
            fx: fx,
            currency: currency,
            truncated: truncated,
            suffix: showOfKin ? currency.ofKinSuffix : nil
        )
    }
}

extension Fiat {
    public func formatted(showOfKin: Bool) -> String {
        NumberFormatter.fiat(
            currency: currency,
            truncated: false,
            suffix: showOfKin ? currency.ofKinSuffix : nil
        ).string(from: amount)!
    }
}

private extension CurrencyCode {
    var ofKinSuffix: String {
        (self == .kin) ? " \(Localized.Core.kin)" : " \(Localized.Core.ofKin)"
    }
}
