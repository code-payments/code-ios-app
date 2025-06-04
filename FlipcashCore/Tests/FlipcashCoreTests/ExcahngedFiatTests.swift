//
//  FiatTests.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-01.
//

import Foundation
import Testing
import FlipcashCore

@Suite("ExchangedFiat Tests")
struct ExchangedFiatTests {
    
    @Test("Subtract fee from amount")
    func testSubtractingFeeFromAmount() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Fiat(fiatDecimal: 5.00, currencyCode: .cad),
            rate: .init(fx: 1.37, currency: .cad)
        )
        
        let fee = try Fiat(fiatDecimal: 0.5, currencyCode: .usd)
        
        let result = try exchangedFiat.subtracting(fee: fee)
        
        #expect(exchangedFiat.usdc.quarks == 3_649_635)
        #expect(fee.quarks == 500_000)
        #expect(result.usdc.quarks == 3_149_635)
    }
    
    @Test("Subtract fee too large")
    func testSubtractingFeeTooLarge() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Fiat(fiatDecimal: 0.60, currencyCode: .cad),
            rate: .init(fx: 1.37, currency: .cad)
        )
        
        let fee = try Fiat(fiatDecimal: 0.5, currencyCode: .usd)
        
        #expect(throws: ExchangedFiat.Error.feeLargerThanAmount) {
            try exchangedFiat.subtracting(fee: fee)
        }
    }
    
    @Test("Subtract fee equal to amount")
    func testSubtractingFeeEqualToAmount() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Fiat(fiatDecimal: 0.50, currencyCode: .usd),
            rate: .oneToOne
        )
        
        let fee = try Fiat(fiatDecimal: 0.5, currencyCode: .usd)
        
        #expect(throws: ExchangedFiat.Error.feeLargerThanAmount) {
            try exchangedFiat.subtracting(fee: fee)
        }
    }
}
