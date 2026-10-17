//
//  DecimalDoubleTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Decimal.doubleValue")
struct DecimalDoubleTests {

    // `native_amount` goes on the wire as a double, and Android's
    // `BigDecimal.toDouble()` is correctly rounded. Each value must land on the
    // same double `Double(String)` parses. 0.007, 0.000001 and the Int64-max
    // amount were each off by an ulp or more when the conversion divided by ten
    // once per decimal digit.
    @Test("Converts to the correctly rounded double", arguments: [
        "0.001",
        "0.007",
        "0.000001",
        "0.8",
        "0.2",
        "4.95",
        "123456789.123456789",
        "9223372036854.775807",
        "-0.007",
        "100000000000000000000",
    ])
    func correctlyRounded(_ string: String) throws {
        let decimal = try #require(Decimal(string: string))
        let expected = try #require(Double(string))
        #expect(decimal.doubleValue == expected)
    }

    @Test("Native amounts in the multi-payment intent vectors convert exactly", arguments: [
        "0.800000", "0.200000", "9223372036854.775807", "0.000001",
        "0.001000", "0.002000", "0.003000", "0.004000", "0.005000",
        "0.006000", "0.007000", "0.008000", "0.009000", "0.010000",
    ])
    func multiPaymentVectorAmounts(_ string: String) throws {
        let decimal = try #require(Decimal(string: string))
        let expected = try #require(Double(string))
        #expect(decimal.doubleValue == expected)
    }

    @Test("Zero and NaN")
    func zeroAndNaN() {
        #expect(Decimal.zero.doubleValue == 0)
        #expect(Decimal.nan.doubleValue.isNaN)
    }
}
