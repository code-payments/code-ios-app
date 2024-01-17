//
//  KinTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class KinTests: XCTestCase {

    func testInitWithKin() {
        XCTAssertEqual(Kin(kin: 1)!.quarks, 100_000)
        
        XCTAssertEqual(Kin(kin: 1 / 3 + 1 as Decimal)!.quarks, 133_334)
        XCTAssertEqual(Kin(kin: 2 / 3 + 1 as Decimal)!.quarks, 166_667)
        
        XCTAssertEqual(Kin(kin: 1 / 3 + 1)!.quarks, 100_000)
        XCTAssertEqual(Kin(kin: 2 / 3 + 1)!.quarks, 100_000)
        
        XCTAssertNil(Kin(kin: -5.0))
        XCTAssertNil(Kin(kin: -5))
        XCTAssertNil(Kin(quarks: -5))
    }
    
    func testInitNegativeKin() {
        XCTAssertNil(Kin(kin: -1))
        XCTAssertNil(Kin(quarks: -1))
        
        XCTAssertNotNil(Kin(kin: -0))
        XCTAssertNotNil(Kin(quarks: -0))
    }
    
    func testInitWithQuarks() {
        XCTAssertEqual(Kin(quarks: 100_000).quarks, 100_000)
        XCTAssertEqual(Kin(quarks: 133_334).quarks, 133_334)
        XCTAssertEqual(Kin(quarks: 166_667).quarks, 166_667)
    }
    
    func testKinValues() {
        XCTAssertEqual(Kin(quarks: 100_000).truncatedKinValue, 1)
        XCTAssertEqual(Kin(quarks: 133_334).truncatedKinValue, 1)
        XCTAssertEqual(Kin(quarks: 166_667).truncatedKinValue, 1)
    }
    
    func testComparison() {
        XCTAssertTrue(Kin(quarks: 13) > Kin(quarks: 12))
        XCTAssertTrue(Kin(quarks: 11) < Kin(quarks: 12))
        XCTAssertTrue(Kin(quarks: 13) >= Kin(quarks: 13))
        XCTAssertTrue(Kin(quarks: 14) >= Kin(quarks: 13))
        XCTAssertTrue(Kin(quarks: 12) <= Kin(quarks: 12))
        XCTAssertTrue(Kin(quarks: 11) <= Kin(quarks: 12))
    }
    
    func testTruncation() {
        XCTAssertEqual(Kin(quarks: 100_000).truncating().quarks, 100_000)
        XCTAssertEqual(Kin(quarks: 133_334).truncating().quarks, 100_000)
        XCTAssertEqual(Kin(quarks: 166_667).truncating().quarks, 100_000)
    }
    
    func testInflation() {
        XCTAssertEqual(Kin(quarks:  99_999).inflating().quarks, 100_000)
        XCTAssertEqual(Kin(quarks: 100_000).inflating().quarks, 100_000)
        XCTAssertEqual(Kin(quarks: 133_334).inflating().quarks, 200_000)
        XCTAssertEqual(Kin(quarks: 166_667).inflating().quarks, 200_000)
    }
    
    func testFractionalQuarks() {
        XCTAssertEqual(Kin(quarks: 100_000).fractionalQuarks, 0)
        XCTAssertEqual(Kin(quarks: 133_334).fractionalQuarks, 33_334)
        XCTAssertEqual(Kin(quarks: 166_667).fractionalQuarks, 66_667)
    }
    
    func testMultiplication() {
        XCTAssertEqual(Kin(kin: 123) * 1_000, Kin(kin: 123_000))
        XCTAssertEqual(Kin(kin: 123) * 1, Kin(kin: 123))
        XCTAssertEqual(Kin(kin: 123) * 0, Kin(kin: 0))
    }
    
    func testDivision() {
        XCTAssertEqual(Kin(kin: 100_000) / 10, 10_000)
        XCTAssertEqual(Kin(kin: 123) / 10, 12)
        XCTAssertEqual(Kin(kin: 123) / 1, 123)
    }
    
    func testSubtraction() {
        XCTAssertEqual(Kin(kin: 100_000) - 10, 99_990)
        XCTAssertEqual(Kin(kin: 123) - 100, 23)
        XCTAssertEqual(Kin(kin: 10) - 90, 0)
    }
    
    func testWholeKin() {
        XCTAssertFalse(Kin(quarks: 123)!.hasWholeKin)
        XCTAssertFalse(Kin(quarks: 99_000)!.hasWholeKin)
        
        XCTAssertTrue(Kin(quarks: 100_000)!.hasWholeKin)
        XCTAssertTrue(Kin(quarks: 123_000)!.hasWholeKin)
    }
}
