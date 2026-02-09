//
//  BigDecimal.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-02-07.
//

import BigDecimal

extension BigDecimal {    
    func pow10(_ n: Int) -> BigDecimal {
        BigDecimal.ten.pow(n, Rounding(.toNearestOrEven, 70))
    }
    
    func scaleDown(_ d: Int) -> BigDecimal {
        divide(pow10(d), Rounding(.toNearestOrEven, 70))
    }
    
    func scaleUp(_ d: Int) -> BigDecimal {
        multiply(pow10(d), Rounding(.toNearestOrEven, 70))
    }
}
