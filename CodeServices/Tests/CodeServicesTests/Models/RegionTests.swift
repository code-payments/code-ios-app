//
//  RegionTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class RegionTests: XCTestCase {
    
    private let excludedRegions: Set<String> = [
        "dg",
        "ea",
        "ic",
        "xk",
    ]
    
    func testAvailableCurrenciesMatchDefinitions() {
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            
            if
                let currencyCode = locale.currencyCode,
                let regionCode = locale.regionCode
            {
                let currency = CurrencyCode(currencyCode: currencyCode)
                let region   = Region(regionCode: regionCode)
                
                XCTAssertNotNil(currency, "Currency code not defined: \(currencyCode)")
                
                guard !excludedRegions.contains(regionCode.lowercased()) else {
                    continue
                }
                
                XCTAssertNotNil(region, "Region code not defined: \(regionCode)")
            }
        }
    }
}
