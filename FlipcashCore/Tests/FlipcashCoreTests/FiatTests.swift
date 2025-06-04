//
//  FiatTests.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-01.
//

import Foundation
import Testing
import FlipcashCore

//@Suite("Fiat Tests")
//struct FiatTests {
//    
//    // MARK: - Initialization Tests
//    
//    @Test("Initialize with quarks and currency code")
//    func testQuarksInit() {
//        let fiat: Fiat = Fiat(quarks: 1_000_000, currencyCode: .usd)
//        #expect(fiat.quarks == 1_000_000)
//        #expect(fiat.currencyCode == .usd)
//    }
//    
//    @Test("Initialize with positive Decimal")
//    func testDecimalInitSuccess() {
//        let fiat = Fiat(fiat: Decimal(1.5), currencyCode: .usd)
//        #expect(fiat != nil)
//        #expect(fiat?.quarks == 1_500_000)
//        #expect(fiat?.currencyCode == .usd)
//    }
//    
//    @Test("Initialize with negative Decimal fails")
//    func testDecimalInitFailure() {
//        let fiat = Fiat(fiat: Decimal(-1.5), currencyCode: .usd)
//        #expect(fiat == nil)
//    }
//    
//    @Test("Initialize with positive Int")
//    func testIntInitSuccess() {
//        let fiat = Fiat(fiat: 2, currencyCode: .usd)
//        #expect(fiat != nil)
//        #expect(fiat?.quarks == 2_000_000)
//        #expect(fiat?.currencyCode == .usd)
//    }
//    
//    @Test("Initialize with negative Int fails")
//    func testIntInitFailure() {
//        let fiat = Fiat(fiat: -2, currencyCode: .usd)
//        #expect(fiat == nil)
//    }
//    
//    @Test("Initialize with UInt64")
//    func testUInt64Init() {
//        let fiat = Fiat(fiat: 3, currencyCode: .usd)!
//        #expect(fiat.quarks == 3_000_000)
//        #expect(fiat.currencyCode == .usd)
//    }
//    
//    @Test("Initialize with positive Int64")
//    func testInt64InitSuccess() {
//        let fiat: Fiat? = Fiat(quarks: 4, currencyCode: .usd)
//        #expect(fiat != nil)
//        #expect(fiat?.quarks == 4)
//        #expect(fiat?.currencyCode == .usd)
//    }
//    
//    @Test("Initialize with negative Int64 fails")
//    func testInt64InitFailure() {
//        let fiat = Fiat(quarks: Int64(-4), currencyCode: .usd)
//        #expect(fiat == nil)
//    }
//    
//    // MARK: - Fee Calculation Tests
//    
//    @Test("Calculate fee with basis points")
//    func testCalculateFee() {
//        let fiat: Fiat = 1
//        let fee = fiat.calculateFee(bps: 50) // 0.5%
//        #expect(fee.quarks == 5_000)
//        #expect(fee.currencyCode == .usd)
//    }
//    
//    // MARK: - Formatting Tests
//    
//    @Test("Formatted string without suffix")
//    func testFormattedNoSuffix() {
//        let fiat: Fiat = 1.50
//        let formatted = fiat.formatted(suffix: nil)
//        #expect(formatted == "$1.50")
//    }
//    
//    @Test("Formatted string with suffix")
//    func testFormattedWithSuffix() {
//        let fiat: Fiat = 1.50
//        let formatted = fiat.formatted(suffix: " USD")
//        #expect(formatted == "$1.50 USD")
//    }
//    
//    // MARK: - Description Tests
//    
//    @Test("Custom string description")
//    func testDescription() {
//        let fiat: Fiat = 2.00
//        #expect(fiat.description == "$2.00")
//        #expect(fiat.debugDescription == "$2.00")
//    }
//    
//    // MARK: - Conversion Tests
//    
//    @Test("Convert to another currency")
//    func testConversion() {
//        let fiat: Fiat = 1.00
//        let rate = Rate(fx: 0.85, currency: .eur)
//        let converted = fiat.converting(to: rate)
//        #expect(converted.quarks == 850_000)
//        #expect(converted.currencyCode == .eur)
//    }
//    
//    // MARK: - Literal Initialization Tests
//    
//    @Test("Integer literal initialization")
//    func testIntegerLiteral() {
//        let fiat: Fiat = 5
//        #expect(fiat.quarks == 5_000_000)
//        #expect(fiat.currencyCode == .usd)
//    }
//    
//    @Test("Float literal initialization")
//    func testFloatLiteral() {
//        let fiat: Fiat = 2.25
//        #expect(fiat.quarks == 2_250_000)
//        #expect(fiat.currencyCode == .usd)
//    }
//    
//    // MARK: - Comparable Tests
//    
//    @Test("Compare less than")
//    func testLessThan() {
//        let fiat1 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        let fiat2 = Fiat(quarks: UInt64(2_000_000), currencyCode: .usd)
//        #expect(fiat1 < fiat2)
//        #expect(!(fiat2 < fiat1))
//    }
//    
//    @Test("Compare less than or equal")
//    func testLessThanOrEqual() {
//        let fiat1 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        let fiat2 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        #expect(fiat1 <= fiat2)
//        #expect(fiat2 <= fiat1)
//    }
//    
//    @Test("Compare greater than")
//    func testGreaterThan() {
//        let fiat1 = Fiat(quarks: UInt64(2_000_000), currencyCode: .usd)
//        let fiat2 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        #expect(fiat1 > fiat2)
//        #expect(!(fiat2 > fiat1))
//    }
//    
//    @Test("Compare greater than or equal")
//    func testGreaterThanOrEqual() {
//        let fiat1 = Fiat(quarks: UInt64(2_000_000), currencyCode: .usd)
//        let fiat2 = Fiat(quarks: UInt64(2_000_000), currencyCode: .usd)
//        #expect(fiat1 >= fiat2)
//        #expect(fiat2 >= fiat1)
//    }
//    
//    // MARK: - Equatable Tests
//    
//    @Test("Equatable conformance")
//    func testEquatable() {
//        let fiat1 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        let fiat2 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        let fiat3 = Fiat(quarks: UInt64(2_000_000), currencyCode: .usd)
//        #expect(fiat1 == fiat2)
//        #expect(fiat1 != fiat3)
//    }
//    
//    // MARK: - Hashable Tests
//    
//    @Test("Hashable conformance")
//    func testHashable() {
//        let fiat1 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        let fiat2 = Fiat(quarks: UInt64(1_000_000), currencyCode: .usd)
//        var set = Set<Fiat>()
//        set.insert(fiat1)
//        set.insert(fiat2)
//        #expect(set.count == 1)
//    }
//}
