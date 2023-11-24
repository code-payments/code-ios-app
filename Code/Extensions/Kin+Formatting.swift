//
//  Kin+Formatting.swift
//  Code
//
//  Created by Dima Bart on 2022-03-10.
//

import Foundation
import CodeServices

extension Kin {
    
    func formattedFiat(rate: Rate, truncated: Bool = false, showOfKin: Bool) -> String {
        formattedFiat(fx: rate.fx, currency: rate.currency, truncated: truncated, showOfKin: showOfKin)
    }
        
    func formattedFiat(fx: Decimal, currency: CurrencyCode, truncated: Bool = false, showOfKin: Bool) -> String {
        let suffix = (currency == .kin) ? " \(Localized.Core.kin)" : " \(Localized.Core.ofKin)"
        return formattedFiat(
            fx: fx,
            currency: currency,
            truncated: truncated,
            suffix: showOfKin ? suffix : nil
        )
    }
}
