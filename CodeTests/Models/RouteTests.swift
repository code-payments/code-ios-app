//
//  RouteTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2023-09-12.
//

import XCTest
@testable import Code

class RouteTests: XCTestCase {
    
    func testSupportedRoutes() {
        let urls = [
            "https://app.getcode.com/cash/#/e=HQPkfAZjgpGGANQfUNPKvW",        // Cash (long)
            "https://app.getcode.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW",           // Cash (short)
            "https://app.getcode.com/r/#/otherdata/p=HQPkfAZjgpGGANQfUNPKvW", // Requests
        ]
        
        let routes = urls.compactMap {
            Route(url: URL(string: $0)!)
        }
        
        XCTAssertEqual(routes.count, 3)
        
        routes.enumerated().forEach { index, route in
            switch index {
            case 0:
                XCTAssertEqual(route.fragments.count, 1)
                XCTAssertNotNil(route.fragments[.entropy])
            case 1:
                XCTAssertEqual(route.fragments.count, 1)
                XCTAssertNotNil(route.fragments[.entropy])
            case 2:
                XCTAssertEqual(route.fragments.count, 1)
                XCTAssertNotNil(route.fragments[.payload])
            default:
                XCTFail()
            }
        }
    }
}
