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
