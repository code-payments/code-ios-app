//
//  DataSetTests.swift
//  CodeUITests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeUI

class DataSetTests: XCTestCase {
    
    func testSubset() {
        let dataSet = dataSet()
        
        let subset1 = dataSet.subset(in: 0..<6)
        XCTAssertEqual(subset1.count, 6)
        XCTAssertEqual(subset1.points[0], 10)
        XCTAssertEqual(subset1.points[1], 30)
        XCTAssertEqual(subset1.points[2], 20)
        XCTAssertEqual(subset1.points[3], 40)
        XCTAssertEqual(subset1.points[4], 30)
        XCTAssertEqual(subset1.points[5], 40)
        
        let subset2 = dataSet.subset(in: 5..<8)
        XCTAssertEqual(subset2.count, 3)
        XCTAssertEqual(subset2.points[0], 40)
        XCTAssertEqual(subset2.points[1], 50)
        XCTAssertEqual(subset2.points[2], 60)
    }
    
    private func dataSet() -> DataSet {
        DataSet(
            points: [
                10, 30, 20, 40, 30,
                40, 50, 60, 25, 50,
                90, 70, 80, 90, 70,
                50, 40, 55, 45, 30,
            ],
            baseline: 20
        )
    }
}
