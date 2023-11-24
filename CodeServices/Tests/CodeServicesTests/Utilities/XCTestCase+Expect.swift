//
//  XCTestCase+Expect.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest

extension XCTestCase {
    func XCTExpect(timeout: TimeInterval = 5.0, block: (XCTestExpectation) -> Void) {
        XCTExpectMultiple(1, timeout: timeout) { expectations in
            block(expectations[0])
        }
    }
    
    func XCTExpectMultiple(_ count: Int, timeout: TimeInterval = 5.0, block: ([XCTestExpectation]) -> Void) {
        let expectations = (0..<count).map { expectation(description: "Arbitrary expectation \($0)") }
        block(expectations)
        wait(for: expectations, timeout: timeout)
    }
    
    func XCTAssertError<T>(_ type: T.Type, error: T, block: () throws -> Void) where T: Equatable {
        do {
            try block()
            XCTFail("Expected \(error) but received no errors.")
        } catch let receivedError as T {
            XCTAssertEqual(error, receivedError)
        } catch let receivedError {
            XCTFail("Expected \(error) but received \(receivedError)")
        }
    }
}
