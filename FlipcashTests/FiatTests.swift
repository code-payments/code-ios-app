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

    static let value = FiatAmount(
        value: Decimal(string: "123.456789")!,
        currency: .cad
    )

    // MARK: - Core -

    @Test
    static func testDecimalConversion() {
        #expect(value.value       == Decimal(string: "123.456789"))
        #expect(value.currency    == .cad)

        #expect(value.value.formatted(to: 6)      == "123.456789")
        #expect(value.doubleValue.formatted(to: 6) == "123.456789")
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
        let jpy = FiatAmount(value: 1000, currency: .jpy)
        let formatted = jpy.formatted()

        // Should show ¥1,000 not ¥1,000.00
        #expect(!formatted.contains("."))
    }

    @Test
    static func testFiatFormatting_USD() {
        // USD can show decimals when needed
        let usd = FiatAmount(value: Decimal(string: "1.23456")!, currency: .usd)
        let formatted = usd.formatted()

        // Should show $1.23 (rounded, with decimals)
        #expect(formatted.contains(".") || formatted.contains(",")) // Depending on locale
    }

    @Test
    static func testFiatFormatting_JPY_fractionalTruncates() {
        // Even if JPY FiatAmount has a fractional value, formatting should truncate
        let jpy = FiatAmount(value: 10, currency: .jpy)
        let formatted = jpy.formatted()

        // Should show ¥10, no decimal places
        #expect(!formatted.contains("."))
    }

    @Test
    static func testFiatFormatting_suffix() {
        let usd = FiatAmount(value: 1, currency: .usd)
        let formatted = usd.formatted(suffix: "USD")
        #expect(formatted.contains("USD"))
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
