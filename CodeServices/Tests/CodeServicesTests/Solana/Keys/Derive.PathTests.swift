//
//  Derive.PathTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class DerivePathTests: XCTestCase {
    
    func testHardenedPath() throws {
        let string = "m/44'/501'/0'/1'"
        let path = try XCTUnwrap(Derive.Path(string))
        
        XCTAssertEqual(path.indexes.count, 4)
        XCTAssertEqual(path.indexes[0], Derive.Path.Index(value: 44,  hardened: true))
        XCTAssertEqual(path.indexes[1], Derive.Path.Index(value: 501, hardened: true))
        XCTAssertEqual(path.indexes[2], Derive.Path.Index(value: 0,   hardened: true))
        XCTAssertEqual(path.indexes[3], Derive.Path.Index(value: 1,   hardened: true))
    }
    
    func testMixedPath() throws {
        let string = "m/44'/501'/0"
        let path = try XCTUnwrap(Derive.Path(string))
        
        XCTAssertEqual(path.indexes.count, 3)
        XCTAssertEqual(path.indexes[0], Derive.Path.Index(value: 44,  hardened: true))
        XCTAssertEqual(path.indexes[1], Derive.Path.Index(value: 501, hardened: true))
        XCTAssertEqual(path.indexes[2], Derive.Path.Index(value: 0,   hardened: false))
    }
    
    func testMasterPath() throws {
        let string = "m"
        let path = try XCTUnwrap(Derive.Path(string))
        
        XCTAssertEqual(path.indexes.count, 0)
    }
    
    func testInvalidPath() throws {
        let string = "44'/501'/0"
        let path = Derive.Path(string)
        
        XCTAssertNil(path)
    }
    
    func testInvalidIndex() throws {
        let string = "m/44'/501'/a/1'"
        let path = Derive.Path(string)
        
        XCTAssertNil(path)
    }
    
    func testEquality() {
        let path1 = Derive.Path("m/44'/501'/0")
        let path2 = Derive.Path("m/44'/501'/0")
        XCTAssertEqual(path1, path2)
    }
    
    func testStringRepresentation() {
        let path = Derive.Path(indexes: [
            .init(value: 44, hardened: true),
            .init(value: 501, hardened: true),
            .init(value: 0, hardened: true),
            .init(value: 12, hardened: false),
        ])
        
        let expectation = "m/44'/501'/0'/12"
        XCTAssertEqual(path.stringRepresentation, expectation)
        XCTAssertEqual(path.description, expectation)
    }
}
