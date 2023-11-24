//
//  RedundancyContainerTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2021-01-28.
//

import Foundation

import XCTest
@testable import Code

class RedundancyContainerTests: XCTestCase {
    
    func testEmptyContainer() {
        var container = RedundancyContainer<String>(threshold: 5)
        let value = "123"
        
        XCTAssertEqual(container.value, nil)
        for _ in 0..<4 {
            container.insert(value)
            XCTAssertEqual(container.value, nil)
        }
        
        container.insert(value)
        XCTAssertEqual(container.value, value)
    }
    
    func testMixedInputsContainer() {
        var container = RedundancyContainer<String>(threshold: 5)
        let value1 = "123"
        let value2 = "234"
        
        XCTAssertEqual(container.value, nil)
        for _ in 0..<4 {
            container.insert(value1)
            XCTAssertEqual(container.value, nil)
        }
        
        XCTAssertEqual(container.value, nil)
        for _ in 0..<4 {
            container.insert(value2)
            XCTAssertEqual(container.value, nil)
        }
        
        container.insert(value1)
        XCTAssertEqual(container.value, value1)
        
        // Value2 should be removed at this point
        
        for _ in 0..<4 {
            container.insert(value2)
        }
        
        // Should still be value1
        XCTAssertEqual(container.value, value1)
        
        for _ in 0..<4 {
            container.insert(value2)
        }
        XCTAssertEqual(container.value, value2)
    }
}
