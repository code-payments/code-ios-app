//
//  KeyPadAmountParsingTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-06-09.
//

import Foundation
import Testing
import FlipcashUI

@Suite struct KeyPadAmountParsingTests {

    @Test("Comma-locale keypad input keeps its fractional part")
    func commaSeparator_keepsFraction() {
        #expect(KeyPadView.amount(from: "1,50", separator: ",") == Decimal(string: "1.5"))
    }

    @Test("Dot-locale keypad input parses unchanged")
    func dotSeparator_keepsFraction() {
        #expect(KeyPadView.amount(from: "1.50", separator: ".") == Decimal(string: "1.5"))
    }

    @Test("Empty input returns nil")
    func emptyInput_returnsNil() {
        #expect(KeyPadView.amount(from: "", separator: ",") == nil)
    }

    @Test("Trailing separator parses as the integer part")
    func trailingSeparator_parsesIntegerPart() {
        #expect(KeyPadView.amount(from: "5,", separator: ",") == 5)
    }

    @Test("Integer-only input is unaffected by the separator")
    func integerOnly_parses() {
        #expect(KeyPadView.amount(from: "150", separator: ",") == 150)
    }
}
