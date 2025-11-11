//
//  CurrencyDecimalPlacesTest.swift
//  FlipcashTests
//
//  Created by Claude on 2025-11-11.
//

import Foundation
import Testing
import FlipcashCore

struct CurrencyDecimalPlacesTest {

    @Test
    static func printAllCurrencyDecimalPlaces() {
        var decimalCounts: [Int: [CurrencyCode]] = [:]

        for currency in CurrencyCode.allCases {
            let decimals = currency.maximumFractionDigits
            if decimalCounts[decimals] == nil {
                decimalCounts[decimals] = []
            }
            decimalCounts[decimals]?.append(currency)
        }

        print("\n=== Currency Decimal Places Summary ===")
        for decimals in decimalCounts.keys.sorted() {
            let currencies = decimalCounts[decimals]!
            print("\n\(decimals) decimal place(s): \(currencies.count) currencies")
            print("Examples: \(currencies.prefix(10).map { $0.rawValue.uppercased() }.joined(separator: ", "))")
        }
        print("\n")

        // The test always passes - we just want to see the output
        #expect(true)
    }
}
