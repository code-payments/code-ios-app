//
//  IntentPublicTransferTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class IntentPublicTransferTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    private lazy var owner = DerivedKey(path: .solana, keyPair: mnemonic.solanaKeyPair())
 
    func testSendTenDollars() throws {
        let organizer = Organizer(mnemonic: mnemonic)
        
        organizer.setBalances([
            .primary: 1_000_000,
        ])
        
        let destination: PublicKey = .mock
        let amount = KinAmount(
            fiat: 10.00,
            rate: Rate(
                fx: 0.00001,
                currency: .usd
            )
        )
        
        let intent = try IntentPublicTransfer(
            organizer: organizer,
            source: .primary,
            destination: .external(destination),
            amount: amount
        )
        
        let resultTray = intent.resultTray
        
        // Ensure outgoing is NOT incremented
        XCTAssertEqual(resultTray.outgoing.cluster.index, organizer.tray.outgoing.cluster.index)
        XCTAssertEqual(organizer.tray.slotsBalance, intent.resultTray.slotsBalance)
        
        XCTAssertEqual(resultTray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(resultTray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(resultTray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(resultTray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(resultTray.slot(for: .bucket10k).partialBalance,  0)
        XCTAssertEqual(resultTray.slot(for: .bucket100k).partialBalance, 0)
        XCTAssertEqual(resultTray.slot(for: .bucket1m).partialBalance,   0)
        
        // Ensure all actions have indexes
        intent.actions.enumerated().forEach { index, action in
            XCTAssertEqual(action.id, index)
        }
        
        XCTAssertEqual(intent.actions.count, 1)
        
        try intent.action(at: 0, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .noPrivacyTransfer)
            XCTAssertEqual(action.amount, amount.kin)
            XCTAssertEqual(action.destination, destination)
        }
    }
    
    func testLocalTransfer() throws {
        let organizer = Organizer(mnemonic: mnemonic)
        let domain = Domain("getcode.com")!
        
        // Setup relationship
        var tray = organizer.tray
        tray.createRelationship(for: domain)
        organizer.set(tray: tray)
        
        // Setup balances
        organizer.setBalances([
            .primary: 1_000_000,
            .relationship(domain): 20_000,
        ])
        
        let amount = KinAmount(kin: 20_000, rate: .oneToOne)
        
        let intent = try IntentPublicTransfer(
            organizer: organizer,
            source: .relationship(domain),
            destination: .local(.primary),
            amount: amount
        )
        
        let resultTray = intent.resultTray
        
        // Ensure outgoing is NOT incremented
        XCTAssertEqual(resultTray.outgoing.cluster.index, organizer.tray.outgoing.cluster.index)
        XCTAssertEqual(organizer.tray.slotsBalance, intent.resultTray.slotsBalance)
        
        XCTAssertEqual(resultTray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(resultTray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(resultTray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(resultTray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(resultTray.slot(for: .bucket10k).partialBalance,  0)
        XCTAssertEqual(resultTray.slot(for: .bucket100k).partialBalance, 0)
        XCTAssertEqual(resultTray.slot(for: .bucket1m).partialBalance,   0)
        
        XCTAssertEqual(resultTray.availableDepositBalance, 1_020_000)
        XCTAssertEqual(resultTray.availableRelationshipBalance, 0)
        
        // Ensure all actions have indexes
        intent.actions.enumerated().forEach { index, action in
            XCTAssertEqual(action.id, index)
        }
        
        XCTAssertEqual(intent.actions.count, 1)
        
        try intent.action(at: 0, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .noPrivacyTransfer)
            XCTAssertEqual(action.amount, amount.kin)
            XCTAssertEqual(action.destination, organizer.primaryVault)
            XCTAssertEqual(action.source, organizer.tray.cluster(for: .relationship(domain)))
        }
    }
}
