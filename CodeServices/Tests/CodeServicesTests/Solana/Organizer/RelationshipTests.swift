//
//  RelationshipTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class RelationshipTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    
    func testDomainDerivation() {
        let relationships = [
            Relationship(domain: Domain("getcode.com")!, mnemonic: mnemonic),
            Relationship(domain: Domain("app.getcode.com")!, mnemonic: mnemonic),
            Relationship(domain: Domain("app.getcode.com", supportSubdomains: true)!, mnemonic: mnemonic),
            Relationship(domain: Domain("example-getcode.com")!, mnemonic: mnemonic),
            Relationship(domain: Domain("https://google-énçøded.com")!, mnemonic: mnemonic),
            Relationship(domain: Domain("https://subdomain.💩.io")!, mnemonic: mnemonic),
            Relationship(domain: Domain("https://subdomain.💩.io", supportSubdomains: true)!, mnemonic: mnemonic),
        ]
        
        print(relationships.map { $0.cluster.vaultPublicKey.base58 })
        
        let expectedKeys = [
            "5fei6CyMWXnYShCGYzc7QfWNpaegRYEHgQsLjwBfyqJD", // getcode.com
            "5fei6CyMWXnYShCGYzc7QfWNpaegRYEHgQsLjwBfyqJD", // app.getcode.com *no subdomain support
            "97dAJxgTSfztnJg5F6WhRn6Rw6bAeub9FJTV9n5TjkY",  // app.getcode.com *with subdomain
            "B8bScuAFQKsVVCGEa8Kj1dPZzkNsCq31AqfecJ9zsJwM", // example-getcode.com
            "2mwTPa8j5g2s47H7oGjx7JFX9ic9uryfb6tNAed2x7EY", // google-énçøded.com
            "Ku42RSuwFTVZMzgYoXhVnZZG2qLH993x3u8oKj4fo1N",  // subdomain.💩.io
            "HxpZV7bKNdexv7UFnKwVhbTLFJdZqnVqqXpr3ur7VSFT", // subdomain.💩.io
        ]
        
        zip(relationships, expectedKeys).forEach { relationship, expected in
            XCTAssertEqual(relationship.cluster.vaultPublicKey.base58, expected)
        }
    }
}

