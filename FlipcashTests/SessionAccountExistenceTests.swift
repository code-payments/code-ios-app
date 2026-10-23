//
//  SessionAccountExistenceTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Destination account existence")
struct SessionAccountExistenceTests {

    @Test("A mint the server already listed skips account creation")
    func knownMintSkips() {
        let mint = PublicKey.generate()!
        #expect(Session.hasAccount(for: mint, knownMints: [PublicKey.generate()!, mint]))
    }

    @Test("A mint never seen keeps the create-account intent")
    func unknownMintCreates() {
        #expect(!Session.hasAccount(for: PublicKey.generate()!, knownMints: [PublicKey.generate()!]))
    }

    @Test("No balances yet keeps the create-account intent")
    func emptyCreates() {
        #expect(!Session.hasAccount(for: PublicKey.generate()!, knownMints: []))
    }
}
