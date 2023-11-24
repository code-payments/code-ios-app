//
//  IntentReceiveTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class IntentReceiveTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    private lazy var owner = DerivedKey(path: .solana, keyPair: mnemonic.solanaKeyPair())
 
    func testReceiveSevenDollars() throws {
        let organizer = Organizer(mnemonic: mnemonic)
        let amount: Kin = 1_000_000
        
        organizer.setBalances([
            .incoming: amount,
        ])
        
        XCTAssertEqual(organizer.tray.availableIncomingBalance, 1_000_000)
        XCTAssertEqual(organizer.tray.slotsBalance, 0)
        
        let previousIncoming = organizer.tray.incoming
        
        let intent = try IntentReceive(
            organizer: organizer,
            amount: amount
        )
        
        XCTAssertNotEqual(intent.id, .zero)
        
        let resultTray = intent.resultTray
        
        // Ensure incoming is incremented
        XCTAssertEqual(resultTray.incoming.cluster.index - 1, organizer.tray.incoming.cluster.index)
        
        // The incoming account has been rotated so we need to ensure
        // the previous incoming account has the correct balance and
        // the new account is empty
        XCTAssertEqual(resultTray.incoming.partialBalance, 0)
        
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
         *  Close Empty   -> G2JXRCvg2PVXHd9veJ5MCcR38723tcuz52Mtw7uE4QK8 (closeEmptyAccount)
         *  Open          -> 7YHmKkV675HNVMpUeFgWssyQZxxFoFG9gRu6RtR2KEfg (openAccount)
         *  Close Dormant -> 7YHmKkV675HNVMpUeFgWssyQZxxFoFG9gRu6RtR2KEfg sending to 8DDrALtni72M6FnCiTMToEssMHDEH3KRP1nhA6svQDxp (closeDormantAccount)
         */
        
        // Ensure all actions have indexes
        intent.actions.enumerated().forEach { index, action in
            XCTAssertEqual(action.id, index)
        }
        
        XCTAssertEqual(intent.actions.count, 10)
        
        try intent.action(at: 0, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyTransfer)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.source, organizer.tray.incoming.cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[6].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 1, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.source, organizer.tray.slots[6].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[5].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 2, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100_000)
            XCTAssertEqual(action.source, organizer.tray.slots[5].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[4].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 3, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10_000)
            XCTAssertEqual(action.source, organizer.tray.slots[4].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[3].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 4, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000)
            XCTAssertEqual(action.source, organizer.tray.slots[3].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[2].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 5, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100)
            XCTAssertEqual(action.source, organizer.tray.slots[2].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[1].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 6, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10)
            XCTAssertEqual(action.source, organizer.tray.slots[1].cluster)
            XCTAssertEqual(action.destination, organizer.tray.slots[0].cluster.timelockAccounts.vault.publicKey)
        }
        
        try intent.action(at: 7, of: ActionCloseEmptyAccount.self) { action in
            XCTAssertEqual(action.type, .incoming)
            XCTAssertEqual(action.cluster, previousIncoming.cluster)
        }
        
        try intent.action(at: 8, of: ActionOpenAccount.self) { action in
            XCTAssertEqual(action.type, .incoming)
            XCTAssertEqual(action.owner, resultTray.owner.cluster.authority.keyPair.publicKey)
            XCTAssertEqual(action.accountCluster, resultTray.incoming.cluster)
        }
        
        try intent.action(at: 9, of: ActionWithdraw.self) { action in
            XCTAssertEqual(action.kind, .closeDormantAccount(.incoming))
            XCTAssertEqual(action.cluster, resultTray.incoming.cluster)
            XCTAssertEqual(action.destination, resultTray.owner.cluster.timelockAccounts.vault.publicKey)
        }
    }
}

extension IntentType {
    func action<T>(at index: Int, of type: T.Type, closure: (T) throws -> Void) throws where T: ActionType {
        guard let action = actions[index] as? T else {
            throw ErrorGeneric.unknown
        }
        
        try closure(action)
    }
}
