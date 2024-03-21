//
//  UUIDTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class UUIDTests: XCTestCase {

    func testMemo() {
        let uuid = UUID(uuidString: "c24a3bf2-ad4f-4756-944e-81948ff10882")!
        let memo = uuid.generateBlockchainMemo()
        
        XCTAssertEqual(memo, "AQAAAAAAwko78q1PR1aUToGUj/EIgg==")
    }
}
