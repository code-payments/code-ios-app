//
//  FiatTests.swift
//  Code
//
//  Created by Dima Bart on 2025-11-04.
//

import Foundation
import Testing
import FlipcashCore

struct FiatTests {
    
    static let value = Quarks(
        quarks: 123_456_789 as UInt64,
        currencyCode: .cad,
        decimals: 6
    )
    
    static let coinValue = Quarks(
        quarks: 123_456_789_000 as UInt64,
        currencyCode: .cad,
        decimals: 10
    )
    
    // MARK: - Core -
    
    @Test
    static func testDecimalConversion() {
        #expect(value.quarks       == 123_456_789)
        #expect(value.currencyCode == .cad)
        #expect(value.decimals     == 6)
        
        #expect(value.decimalValue.formatted(to: 6) == "123.456789")
        #expect(value.doubleValue.formatted(to: 6)  == "123.456789")
    }
    
    @Test
    static func testInvalidValues() throws {
        #expect(throws: Quarks.Error.invalidNegativeValue) {
            try Quarks(quarks: -1 as Int64, currencyCode: .cad, decimals: 6)
        }
        
        #expect(throws: Quarks.Error.invalidNegativeValue) {
            try Quarks(fiatInt: -1 as Int, currencyCode: .cad, decimals: 6)
        }
        
        #expect(throws: Quarks.Error.invalidNegativeValue) {
            try Quarks(fiatDecimal: -0.01 as Decimal, currencyCode: .cad, decimals: 6)
        }
    }
    
    @Test
    static func testMathThrows() throws {
        #expect(throws: Quarks.Error.decimalMismatch) {
            try value.subtracting(coinValue)
        }
        
        #expect(throws: Quarks.Error.decimalMismatch) {
            try value.adding(coinValue)
        }
    }
    
    @Test
    static func testAdditionMatchingDecimals() throws {
        let lhs = Quarks(quarks: 111_111 as UInt64, currencyCode: .cad, decimals: 6)
        let rhs = Quarks(quarks: 222_222 as UInt64, currencyCode: .cad, decimals: 6)
        
        let result = try lhs.adding(rhs)
        
        #expect(result.quarks       == 333_333)
        #expect(result.currencyCode == .cad)
        #expect(result.decimals     == 6)
    }

    // MARK: - Currency Decimal Places -

    @Test
    static func testCurrencyDecimalPlaces_USD() {
        // USD uses 2 decimal places
        #expect(CurrencyCode.usd.maximumFractionDigits == 2)
    }

    @Test
    static func testCurrencyDecimalPlaces_JPY() {
        // JPY uses 0 decimal places (whole yen only)
        #expect(CurrencyCode.jpy.maximumFractionDigits == 0)
    }

    @Test
    static func testCurrencyDecimalPlaces_KRW() {
        // KRW uses 0 decimal places (whole won only)
        #expect(CurrencyCode.krw.maximumFractionDigits == 0)
    }

    @Test
    static func testCurrencyDecimalPlaces_BHD() {
        // BHD uses 3 decimal places
        #expect(CurrencyCode.bhd.maximumFractionDigits == 3)
    }

    @Test
    static func testCurrencyDecimalPlaces_EUR() {
        // EUR uses 2 decimal places
        #expect(CurrencyCode.eur.maximumFractionDigits == 2)
    }

    @Test
    static func testCurrencyDecimalPlaces_CAD() {
        // CAD uses 2 decimal places
        #expect(CurrencyCode.cad.maximumFractionDigits == 2)
    }

    @Test
    static func testFiatFormatting_JPY() {
        // JPY should format without decimal places
        let jpy = Quarks(quarks: 1000 as UInt64, currencyCode: .jpy, decimals: 0)
        let formatted = jpy.formatted()

        // Should show ¥1,000 not ¥1,000.00
        #expect(!formatted.contains("."))
    }

    @Test
    static func testFiatFormatting_USD() {
        // USD can show decimals when needed
        let usd = Quarks(quarks: 1_234_560 as UInt64, currencyCode: .usd, decimals: 6)
        let formatted = usd.formatted()

        // Should show $1.23 (rounded, with decimals)
        #expect(formatted.contains(".") || formatted.contains(",")) // Depending on locale
    }

    @Test
    static func testFiatFormatting_JPY_WithDecimals() {
        // Even if JPY Fiat has fractional quarks, formatting should truncate
        let jpy = Quarks(quarks: 1000 as UInt64, currencyCode: .jpy, decimals: 2)
        let formatted = jpy.formatted()

        // Should show ¥10 (1000 quarks / 100 decimals = 10), no decimal places
        #expect(!formatted.contains("."))
    }

    // MARK: - Comparison Overflow Safety -

    @Test("Comparing CLP quarks across different decimal precisions does not overflow")
    static func testComparison_CLP_doesNotOverflow() {
        // CLP rate ~950:1 USD. Simulate a large CLP amount at 6 decimals
        // being compared with a value at 10 decimals (bonded token).
        // Old code would scaleUp(4) on the 6-decimal value, causing UInt64 overflow.
        //
        // clpAt6:  475_000_000_000_000 / 10^6  = 475,000,000 CLP
        // clpAt10: 1_000_000_000_000_000_000 / 10^10 = 100,000,000 CLP
        let clpAt6  = Quarks(quarks: 475_000_000_000_000 as UInt64, currencyCode: .clp, decimals: 6)
        let clpAt10 = Quarks(quarks: 1_000_000_000_000_000_000 as UInt64, currencyCode: .clp, decimals: 10)

        // This must not crash, and 100M < 475M
        #expect(clpAt10 < clpAt6)
    }

    @Test("Comparing quarks with different decimals produces correct ordering")
    static func testComparison_differentDecimals_correctOrdering() {
        // 100.0 at 6 decimals
        let a = Quarks(quarks: 100_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        // 50.0 at 10 decimals
        let b = Quarks(quarks: 500_000_000_000 as UInt64, currencyCode: .usd, decimals: 10)

        #expect(b < a) // 50 < 100
        #expect(!(a < b))
    }

    @Test(
        "No currency overflows when comparing a high-value quarks amount across 6 and 10 decimal precisions",
        arguments: CurrencyCode.allCases
    )
    static func testComparison_allCurrencies_noOverflow(currency: CurrencyCode) {
        // Use a very large quarks value at 6 decimals (simulating a high-rate
        // currency converted amount near the UInt64 practical limit) and compare
        // with a value at 10 decimals. This must never overflow.
        let largeAt6  = Quarks(quarks: 1_000_000_000_000_000 as UInt64, currencyCode: currency, decimals: 6)
        let largeAt10 = Quarks(quarks: 1_000_000_000_000_000 as UInt64, currencyCode: currency, decimals: 10)

        // 10^15 / 10^6 = 10^9 vs 10^15 / 10^10 = 10^5
        // So largeAt6 represents 1,000,000,000 and largeAt10 represents 100,000
        #expect(largeAt10 < largeAt6)
    }
}


// MARK: - Formatters -

extension Decimal {
    func formatted(to decimalPlaces: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = decimalPlaces
        formatter.maximumFractionDigits = decimalPlaces
        formatter.numberStyle = .decimal
        return formatter.string(for: self) ?? "\(self)"
    }
}

extension Double {
    func formatted(to decimalPlaces: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = decimalPlaces
        formatter.maximumFractionDigits = decimalPlaces
        formatter.numberStyle = .decimal
        return formatter.string(for: self) ?? "\(self)"
    }
}
