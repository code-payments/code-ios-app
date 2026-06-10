//
//  UInt64OperationsTests.swift
//  Flipcash
//
//  Created by Claude on 2026-02-13.
//

import Foundation
import Testing
@testable import FlipcashCore

// MARK: - scaleDown

@Suite("UInt64.scaleDown")
struct UInt64ScaleDownTests {

    @Test("Converts quarks to Decimal by dividing by 10^d")
    func convertsQuarksToDecimal() {
        #expect((123_456_789 as UInt64).scaleDown(6) == Decimal(string: "123.456789"))
    }

    @Test("Value smaller than factor returns a fractional Decimal")
    func smallValue() {
        #expect((1 as UInt64).scaleDown(6) == Decimal(string: "0.000001"))
    }

    @Test("Preserves precision for high-rate currency quarks")
    func highRateCurrencyQuarks() {
        // CLP-scale quarks (6-decimal wire encoding at high FX rates).
        #expect((475_000_000_000_000 as UInt64).scaleDown(6) == Decimal(475_000_000))
    }

    @Test("Works with bonded token precision (10 decimals)")
    func bondedTokenDecimals() {
        #expect((1_000_000_000_000 as UInt64).scaleDown(10) == Decimal(100))
    }
}

// MARK: - scaleUp

@Suite("UInt64.scaleUp")
struct UInt64ScaleUpTests {

    @Test("Multiplies by 10^d")
    func multipliesByFactor() {
        #expect((123 as UInt64).scaleUp(4) == 1_230_000)
    }

    @Test("Zero value stays zero regardless of exponent")
    func zeroValue() {
        #expect((0 as UInt64).scaleUp(10) == 0)
    }

    @Test("Succeeds near the UInt64 boundary without overflow")
    func maxSafeValue() {
        // UInt64.max / 10_000 ≈ 1_844_674_407_370_955
        let quarks: UInt64 = 1_844_674_407_370_955
        #expect(quarks.scaleUp(4) == 18_446_744_073_709_550_000)
    }
}
