//
//  String+PaddingTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2021-04-12.
//

import XCTest
import CodeUI
@testable import Code

class StringPaddingTests: XCTestCase {
    
    func testPaddingNotRequired() {
        let hex = "e6e9ff"
        let padded = hex.addingLeadingZeros(upTo: 6)
        XCTAssertEqual(padded, hex)
    }
    
    func testPaddingOdd() {
        let hex = "e6e9f"
        
        let padded6 = hex.addingLeadingZeros(upTo: 6)
        let padded8 = hex.addingLeadingZeros(upTo: 8)
        let padded10 = hex.addingLeadingZeros(upTo: 10)
        
        XCTAssertEqual(padded6,  "0\(hex)")
        XCTAssertEqual(padded8,  "000\(hex)")
        XCTAssertEqual(padded10, "00000\(hex)")
    }
    
    func testPaddingEven() {
        let hex = "e6e9"
        
        let padded6 = hex.addingLeadingZeros(upTo: 6)
        let padded8 = hex.addingLeadingZeros(upTo: 8)
        let padded10 = hex.addingLeadingZeros(upTo: 10)
        
        XCTAssertEqual(padded6,  "00\(hex)")
        XCTAssertEqual(padded8,  "0000\(hex)")
        XCTAssertEqual(padded10, "000000\(hex)")
    }
}
