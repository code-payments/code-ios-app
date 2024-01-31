//
//  RelationshipBoxTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class RelationshipBoxTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    
    private let domain = Domain("google.com")!
    
    func testInsert() {
        let relationship = Relationship(domain: domain, mnemonic: mnemonic)
        var box = RelationshipBox()

        XCTAssertEqual(box.publicKeys.count, 0)
        XCTAssertEqual(box.domains.count, 0)
        
        box.insert(relationship)
        
        XCTAssertEqual(box.publicKeys.count, 1)
        XCTAssertEqual(box.domains.count, 1)
    }
    
    func testGet() {
        let relationship = Relationship(domain: domain, mnemonic: mnemonic)
        var box = RelationshipBox()
        
        box.insert(relationship)
        
        XCTAssertEqual(box.relationship(for: domain), relationship)
        XCTAssertEqual(box.relationship(for: relationship.cluster.vaultPublicKey), relationship)
    }
    
    func testGetSorted() {
        var relationship1 = Relationship(domain: Domain("getcode.com")!, mnemonic: mnemonic)
        relationship1.partialBalance = 100_000
        
        var relationship2 = Relationship(domain: Domain("google.com")!, mnemonic: mnemonic)
        relationship2.partialBalance = 200_000
        
        var relationship3 = Relationship(domain: Domain("apple.com")!, mnemonic: mnemonic)
        relationship3.partialBalance = 300_000
        
        var box = RelationshipBox()
        
        box.insert(relationship1)
        box.insert(relationship2)
        box.insert(relationship3)
        
        let relationshipsLargest = box.relationships(largestFirst: true)
        XCTAssertEqual(relationshipsLargest.first, relationship3)
        
        let relationshipsSmallest = box.relationships(largestFirst: false)
        XCTAssertEqual(relationshipsSmallest.first, relationship1)
    }
    
    func testRemove() {
        let relationship = Relationship(domain: domain, mnemonic: mnemonic)
        var box = RelationshipBox()
        
        box.insert(relationship)
        box.remove(domain: domain)
        
        XCTAssertEqual(box.publicKeys.count, 0)
        XCTAssertEqual(box.domains.count, 0)
        
        box.insert(relationship)
        box.remove(publicKey: relationship.cluster.vaultPublicKey)
        
        XCTAssertEqual(box.publicKeys.count, 0)
        XCTAssertEqual(box.domains.count, 0)
    }
}
