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
    
    static let value = Fiat(
        quarks: 123_456_789 as UInt64,
        currencyCode: .cad,
        decimals: 6
    )
    
    static let coinValue = Fiat(
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
        #expect(throws: Fiat.Error.invalidNegativeValue) {
            try Fiat(quarks: -1 as Int64, currencyCode: .cad, decimals: 6)
        }
        
        #expect(throws: Fiat.Error.invalidNegativeValue) {
            try Fiat(fiatInt: -1 as Int, currencyCode: .cad, decimals: 6)
        }
        
        #expect(throws: Fiat.Error.invalidNegativeValue) {
            try Fiat(fiatDecimal: -0.01 as Decimal, currencyCode: .cad, decimals: 6)
        }
    }
    
    @Test
    static func testMathThrows() throws {
        #expect(throws: Fiat.Error.decimalMismatch) {
            try value.subtracting(coinValue)
        }
        
        #expect(throws: Fiat.Error.decimalMismatch) {
            try value.adding(coinValue)
        }
    }
    
    @Test
    static func testAdditionMatchingDecimals() throws {
        let lhs = Fiat(quarks: 111_111 as UInt64, currencyCode: .cad, decimals: 6)
        let rhs = Fiat(quarks: 222_222 as UInt64, currencyCode: .cad, decimals: 6)
        
        let result = try lhs.adding(rhs)
        
        #expect(result.quarks       == 333_333)
        #expect(result.currencyCode == .cad)
        #expect(result.decimals     == 6)
    }
    
    @Test
    static func testAdditionMismatchedDecimals() throws {
        let lhs = Fiat(quarks: 1_000_000      as UInt64, currencyCode: .cad, decimals: 6)
        let rhs = Fiat(quarks: 10_000_000_000 as UInt64, currencyCode: .cad, decimals: 10)
        
        let result = try lhs.adding(rhs)
        
        #expect(result.quarks       == 20_000_000_000)
        #expect(result.currencyCode == .cad)
        #expect(result.decimals     == 10)
    }
    
    @Test
    static func testSubtractionMismatchedDecimals() throws {
        let lhs = Fiat(quarks: 70_000_000_000 as UInt64, currencyCode: .cad, decimals: 6)
        let rhs = Fiat(quarks: 5_000_000      as UInt64, currencyCode: .cad, decimals: 10)
        
        let result = try lhs.subtracting(rhs)
        
        #expect(result.quarks       == 20_000_000_000)
        #expect(result.currencyCode == .cad)
        #expect(result.decimals     == 10)
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
