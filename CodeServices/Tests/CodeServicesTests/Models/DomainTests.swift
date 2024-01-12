//
//  DomainTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class DomainTests: XCTestCase {
    
    func testParsing() {
        XCTAssertEqual(Domain("https://💩.domain.com")?.relationshipHost, "domain.com")
        XCTAssertEqual(Domain("https://google.com")?.relationshipHost, "google.com")
        XCTAssertEqual(Domain("http://google.com")?.relationshipHost, "google.com")
        XCTAssertEqual(Domain("https://google-énçøded.com")?.relationshipHost, "xn--google-nded-t9ay6s.com")
        XCTAssertEqual(Domain("https://subdomain.💩.io")?.relationshipHost, "xn--ls8h.io")
        
        XCTAssertEqual(Domain("https://example-domain.com")?.relationshipHost, "example-domain.com")
        XCTAssertEqual(Domain("https://app.example-getcode.com")?.relationshipHost, "example-getcode.com")
        
        // Subdomain
        
        XCTAssertEqual(Domain("https://app.getcode.com", supportSubdomains: false)?.relationshipHost, "getcode.com")
        XCTAssertEqual(Domain("https://app.getcode.com", supportSubdomains: true)?.relationshipHost, "app.getcode.com")
        XCTAssertEqual(Domain("https://💩.domain.com", supportSubdomains: false)?.relationshipHost, "domain.com")
        XCTAssertEqual(Domain("https://💩.domain.com", supportSubdomains: true)?.relationshipHost, "xn--ls8h.domain.com")
    }
    
    func testNoScheme() {
        let domain = Domain("google.com")
        XCTAssertEqual(domain?.relationshipHost, "google.com")
        XCTAssertEqual(domain?.urlString, "google.com")
    }
    
    func testInit() {
        let domain = Domain("https://www.google.com")
        XCTAssertEqual(domain?.relationshipHost, "google.com")
        XCTAssertEqual(domain?.urlString, "https://www.google.com")
    }
    
    func testMultisubdomain() {
        let domain = Domain("https://api.test.google.com")
        XCTAssertEqual(domain?.relationshipHost, "google.com")
        XCTAssertEqual(domain?.urlString, "https://api.test.google.com")
    }
}
