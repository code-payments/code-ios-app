//
//  IntentDepositTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class IntentDepositTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    private lazy var owner = DerivedKey(path: .solana, keyPair: mnemonic.solanaKeyPair())
 
    func testReceiveSevenDollars() throws {
        let organizer = Organizer(mnemonic: mnemonic)
        let amount: Kin = 1_000_000
        
        organizer.setBalances([
            .primary: amount,
        ])
        
        XCTAssertEqual(organizer.tray.availableDepositBalance, 1_000_000)
        XCTAssertEqual(organizer.tray.slotsBalance, 0)
        
        let intent = try IntentDeposit(
            source: .primary,
            organizer: organizer,
            amount: amount
        )
        
        XCTAssertNotEqual(intent.id, .zero)
        
        let resultTray = intent.resultTray
        
        // Ensure the funds have been moved out of the
        // primary accounts and into the tray slots
        XCTAssertEqual(resultTray.owner.partialBalance, 0)
        
        XCTAssertEqual(resultTray.slotsBalance,    1_000_000)
        XCTAssertEqual(resultTray.owner.partialBalance,    0)
        XCTAssertEqual(resultTray.incoming.partialBalance, 0)
        XCTAssertEqual(resultTray.outgoing.partialBalance, 0)
        
        XCTAssertEqual(resultTray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(resultTray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(resultTray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(resultTray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(resultTray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(resultTray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(resultTray.slot(for: .bucket1m).partialBalance,   0)
        
        /*
         *  Expected actions:
         *
         *  K 1000000 (0) -> AB4w6m9nhQaagqpnu6TcsgE1Z34wXKwKSoxU6tGadAfN (tempPrivacyTransfer)
         *  K 1000000 (0) -> BEZasPLNZ5vsHH3SfdxeWuTD5uXm8pPUmbyrZkPJqQwr (tempPrivacyExchange)
         *  K 100000 (0)  -> 7GpxPmL2sGqRq1ru4nKTPWPRruemat5BCReGmNLNXsRE (tempPrivacyExchange)
         *  K 10000 (0)   -> 6upXkqkiY3GYBqm3wSReuAsaWxQSY1d67GuRxLhM74Va (tempPrivacyExchange)
         *  K 1000 (0)    -> 6eqAKwBqtAQ28juRdc3429GoRpUTuu86gScJrDN6cqGQ (tempPrivacyExchange)
         *  K 100 (0)     -> BbCteP1N7DiyShnEuCRGkNLeoYbr7v1d5deGDBbeu5Zg (tempPrivacyExchange)
         *  K 10 (0)      -> J5fzggJmRyPwmAcJw7iVD9jG4q4xZyeELNEEjfhKxp4i (tempPrivacyExchange)
         */
        
        // Ensure all actions have indexes
        intent.actions.enumerated().forEach { index, action in
            XCTAssertEqual(action.id, index)
        }
        
        XCTAssertEqual(intent.actions.count, 7)
        
        try intent.action(at: 0, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyTransfer)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.source, organizer.tray.owner.cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[6].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 1, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.source, organizer.tray.slots[6].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[5].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 2, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100_000)
            XCTAssertEqual(action.source, organizer.tray.slots[5].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[4].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 3, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10_000)
            XCTAssertEqual(action.source, organizer.tray.slots[4].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[3].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 4, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000)
            XCTAssertEqual(action.source, organizer.tray.slots[3].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[2].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 5, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100)
            XCTAssertEqual(action.source, organizer.tray.slots[2].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[1].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 6, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10)
            XCTAssertEqual(action.source, organizer.tray.slots[1].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[0].cluster.vaultPublicKey)
        }
    }
    
    func testReceiveRelationshipSevenDollars() throws {
        let domain = Domain("google.com")!
        let organizer = Organizer(mnemonic: mnemonic)
        let amount: Kin = 1_000_000
        
        var tray = organizer.tray
        tray.createRelationship(for: domain)
        organizer.set(tray: tray)
        
        organizer.setBalances([
            .relationship(domain): amount,
        ])
        
        XCTAssertEqual(organizer.tray.availableRelationshipBalance, 1_000_000)
        XCTAssertEqual(organizer.tray.slotsBalance, 0)
        
        let intent = try IntentDeposit(
            source: .relationship(domain),
            organizer: organizer,
            amount: amount
        )
        
        XCTAssertNotEqual(intent.id, .zero)
        
        let resultTray = intent.resultTray
        
        // Ensure the funds have been moved out of the
        // relationship account and into the tray slots
        XCTAssertEqual(resultTray.relationships.relationship(for: domain)!.partialBalance, 0)
        
        XCTAssertEqual(resultTray.slotsBalance,    1_000_000)
        XCTAssertEqual(resultTray.owner.partialBalance,    0)
        XCTAssertEqual(resultTray.incoming.partialBalance, 0)
        XCTAssertEqual(resultTray.outgoing.partialBalance, 0)
        
        XCTAssertEqual(resultTray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(resultTray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(resultTray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(resultTray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(resultTray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(resultTray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(resultTray.slot(for: .bucket1m).partialBalance,   0)
        
        /*
         *  Expected actions:
         *
         *  K 1000000 (0) -> AB4w6m9nhQaagqpnu6TcsgE1Z34wXKwKSoxU6tGadAfN (tempPrivacyTransfer)
         *  K 1000000 (0) -> BEZasPLNZ5vsHH3SfdxeWuTD5uXm8pPUmbyrZkPJqQwr (tempPrivacyExchange)
         *  K 100000 (0)  -> 7GpxPmL2sGqRq1ru4nKTPWPRruemat5BCReGmNLNXsRE (tempPrivacyExchange)
         *  K 10000 (0)   -> 6upXkqkiY3GYBqm3wSReuAsaWxQSY1d67GuRxLhM74Va (tempPrivacyExchange)
         *  K 1000 (0)    -> 6eqAKwBqtAQ28juRdc3429GoRpUTuu86gScJrDN6cqGQ (tempPrivacyExchange)
         *  K 100 (0)     -> BbCteP1N7DiyShnEuCRGkNLeoYbr7v1d5deGDBbeu5Zg (tempPrivacyExchange)
         *  K 10 (0)      -> J5fzggJmRyPwmAcJw7iVD9jG4q4xZyeELNEEjfhKxp4i (tempPrivacyExchange)
         */
        
        // Ensure all actions have indexes
        intent.actions.enumerated().forEach { index, action in
            XCTAssertEqual(action.id, index)
        }
        
        XCTAssertEqual(intent.actions.count, 7)
        
        try intent.action(at: 0, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyTransfer)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.source, organizer.tray.cluster(for: .relationship(domain)))
            XCTAssertEqual(action.destination, organizer.tray.slots[6].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 1, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.source, organizer.tray.slots[6].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[5].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 2, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100_000)
            XCTAssertEqual(action.source, organizer.tray.slots[5].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[4].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 3, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10_000)
            XCTAssertEqual(action.source, organizer.tray.slots[4].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[3].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 4, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000)
            XCTAssertEqual(action.source, organizer.tray.slots[3].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[2].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 5, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100)
            XCTAssertEqual(action.source, organizer.tray.slots[2].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[1].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 6, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10)
            XCTAssertEqual(action.source, organizer.tray.slots[1].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[0].cluster.vaultPublicKey)
        }
    }
}
