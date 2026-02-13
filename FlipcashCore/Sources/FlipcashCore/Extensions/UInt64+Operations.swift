//
//  Decimal+Operations.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-02-07.
//

import Foundation

extension UInt64 {
    private func pow10(_ n: Int) -> UInt64 {
        return (0..<n).reduce(1) { acc, _ in acc * 10 }
    }
    
    func scaleDown(_ d: Int) -> Decimal {
        let factor = Decimal(pow10(d))
        return Decimal(self) / factor
    }
    
    func scaleDownInt(_ d: Int) -> UInt64 {
        let factor = pow10(d)
        return self / factor
    }

    func scaleUp(_ d: Int) -> UInt64 {
        let factor = pow10(d)
        let (result, overflow) = self.multipliedReportingOverflow(by: factor)
        precondition(!overflow, "UInt64.scaleUp overflow: \(self) * 10^\(d)")
        return result
    }
}
