//
//  String+PaddingTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2021-04-12.
//

import XCTest
import CodeUI
import CodeServices
@testable import Code

class StringPaddingTests: XCTestCase {
    
    // MARK: - Padding -
    
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
    
    // MARK: - Base64 -
    
    func testBase64DecodeWithPadding() {
        let cases = [
            "UF9GiYNrZIaJkMI8x1uszkSjpzorzZedmd3yohqwX0w=",
            "5cTK9FWY//svGYh5L1Eexo8r0zg4+lv78I/WIjoSCw==",
            "mFTI5b8lP2lzOWe+m7uMm9O30zEXDlQE7+kMg02V",
            "tp0vmC+vacmnofMvrvkCQQBPbfqWOMTIds1NyWc=",
            "T4jfUmKkQ2IDljupFXl0lMIoHeM73urTyj09DQ==",
            "RD+6UECHg825Cdo4w2lY115rqHoxrovvnw6U",
            "6qI22/ljQgmGmWfu0vPVFq7lzVAGYzD8yXA=",
            "YEjg0HKhaAbszV0vOMVXMt15dIpUMA6dvg==",
            "VR/n6bmMFdzM3n/gfqrrXjiT6h3niP5b",
            "Bdetc6nHhi9blf66VOrd1bxEfCr1Lyg=",
            "ZymLkvPeaMCWqQYybIGAacGx1DBr1A==",
            "ai7C0CjsXStNDvBD+m+bVi7NVvIZ",
            "4A6wWJvgOmlziw3w4PtLrfi0nLg=",
            "12vQN0D3JqXt9A4lL/Gl3ytFGg==",
            "mMoTeErSzNT+NjstO3/MQINB",
            "kM1/Qp/RZ9JmpwPho3a9x0I=",
            "Cj9x+xq42VK9Zy6nbh3X5g==",
            "qCO/M3Qc5SXXDVzcqm4F",
            "428FL5j7tJn5dP7n3pY=",
            "qOH389COiRqFUxXssA==",
            "C+WOiUxKy0/30t0Z",
            "f8lhjZMVAeHUI6w=",
            "GZ9be+8GdD4d5g==",
            "A5qhV7APKY7h",
            "ww/ulPB94FI=",
        ]
        
        cases.forEach { c in
            XCTAssertNotNil(c.base64EncodedData())
        }
    }
    
    func testBase64DecodeWithoutPadding() {
        let cases = [
            
            // Missing the last '='
            
            "5cTK9FWY//svGYh5L1Eexo8r0zg4+lv78I/WIjoSCw=",
            "T4jfUmKkQ2IDljupFXl0lMIoHeM73urTyj09DQ=",
            "YEjg0HKhaAbszV0vOMVXMt15dIpUMA6dvg=",
            "ZymLkvPeaMCWqQYybIGAacGx1DBr1A=",
            "12vQN0D3JqXt9A4lL/Gl3ytFGg=",
            "Cj9x+xq42VK9Zy6nbh3X5g=",
            "qOH389COiRqFUxXssA=",
            "GZ9be+8GdD4d5g=",
            
            // Missing all '=='
            
            "5cTK9FWY//svGYh5L1Eexo8r0zg4+lv78I/WIjoSCw",
            "T4jfUmKkQ2IDljupFXl0lMIoHeM73urTyj09DQ",
            "YEjg0HKhaAbszV0vOMVXMt15dIpUMA6dvg",
            "ZymLkvPeaMCWqQYybIGAacGx1DBr1A",
            "12vQN0D3JqXt9A4lL/Gl3ytFGg",
            "Cj9x+xq42VK9Zy6nbh3X5g",
            "qOH389COiRqFUxXssA",
            "GZ9be+8GdD4d5g",
            
            // Not missing any padding
            
            "mFTI5b8lP2lzOWe+m7uMm9O30zEXDlQE7+kMg02V",
            "RD+6UECHg825Cdo4w2lY115rqHoxrovvnw6U",
            "VR/n6bmMFdzM3n/gfqrrXjiT6h3niP5b",
            "ai7C0CjsXStNDvBD+m+bVi7NVvIZ",
            "mMoTeErSzNT+NjstO3/MQINB",
            "qCO/M3Qc5SXXDVzcqm4F",
            "C+WOiUxKy0/30t0Z",
            "A5qhV7APKY7h",
        ]
        
        cases.forEach { c in
            XCTAssertNotNil(c.base64EncodedData())
        }
    }
}
