//
//  EncodingTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2021-01-26.
//

import XCTest
import CodeScanner
@testable import Code

class EncodingTests: XCTestCase {

    func test20Bytes() throws {
        let encoded = KikCodes.encode(.placeholder)
        let decoded = KikCodes.decode(encoded)
        
        XCTAssertEqual(decoded, .placeholder)
    }
    
    func test40Bytes() throws {
        let input = Data([
            0x6D, 0x70, 0x72, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x71,
            0xD8, 0x9E, 0x81, 0x34, 0x63, 0x06, 0xA0, 0x35, 0xA6, 0x83,
            0x6D, 0x70, 0x72, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x71,
            0xD8, 0x9E, 0x81, 0x34, 0x63, 0x06, 0xA0, 0x35, 0xA6, 0x83,
        ])
        let encoded = KikCodes.encode(input)
        let decoded = KikCodes.decode(encoded)
        
        // We expect any overlow to be
        // clipped when encoding the data
        XCTAssertEqual(decoded, input.subdata(in: 0..<20))
    }
    
    func testShortString() throws {
        let input = "pineapplesauce".data(using: .utf8)!
        let encoded = KikCodes.encode(input)
        let decoded = KikCodes.decode(encoded)
        
        XCTAssertEqual(decoded, input)
    }
    
    func testZeroLengthString() throws {
        let input = "".data(using: .utf8)!
        let encoded = KikCodes.encode(input)
        let decoded = KikCodes.decode(encoded)
        
        XCTAssertEqual(decoded, input)
    }
}

extension Data {
    static var placeholder: Data {
        Data([
            0x6D, 0x70, 0x72, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x40, 0x71,
            0xD8, 0x9E, 0x81, 0x34, 0x63,
            0x06, 0xA0, 0x35, 0xA6, 0x83,
        ])
    }
}
