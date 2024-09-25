//
//  IntentPrivateTransferTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class IntentPrivateTransferTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    private lazy var owner = DerivedKey(path: .solana, keyPair: mnemonic.solanaKeyPair())
 
    func testSendFiveDollars() throws {
        let organizer = Organizer(mnemonic: mnemonic)
        
        organizer.setBalances([
            .bucket(.bucket1m): 1_000_000,
        ])
        
        let destination: PublicKey = .mock
        let amount = KinAmount(
            fiat: 5.00,
            rate: Rate(
                fx: 0.00001,
                currency: .usd
            )
        )
        
        let rendezvous = PublicKey.generate()!
        let intent = try IntentPrivateTransfer(
            rendezvous: rendezvous,
            organizer: organizer,
            destination: destination,
            amount: amount,
            fee: 0,
            additionalFees: [],
            isWithdrawal: false,
            tipAccount: nil,
            chatID: nil
        )
        
        XCTAssertEqual(intent.id, rendezvous)
        
        let resultTray = intent.resultTray
        
        // Ensure outgoing is incremented
        XCTAssertEqual(resultTray.outgoing.cluster.index - 1, organizer.tray.outgoing.cluster.index)
        
        // The outgoing account has been rotated so we need to ensure
        // the previous outgoing account has the correct balance and
        // the new account is empty
        XCTAssertEqual(resultTray.outgoing.partialBalance, 0)
        
        XCTAssertEqual(organizer.tray.slotsBalance - intent.resultTray.slotsBalance, 500_000)
        
        XCTAssertEqual(resultTray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(resultTray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(resultTray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(resultTray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(resultTray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(resultTray.slot(for: .bucket100k).partialBalance, 400_000)
        XCTAssertEqual(resultTray.slot(for: .bucket1m).partialBalance,   0)
        
        /*
         *  Expected actions:
         *
         *  K 1000000 (0) -> BEZasPLNZ5vsHH3SfdxeWuTD5uXm8pPUmbyrZkPJqQwr (tempPrivacyExchange)
         *  K 100000 (0)  -> 7GpxPmL2sGqRq1ru4nKTPWPRruemat5BCReGmNLNXsRE (tempPrivacyExchange)
         *  K 500000 (0)  -> Gfuc6w9vPwoGKtRwEv7YJtxGWtR4knLGoMoT5Hu1eS6A (tempPrivacyTransfer)
         *  K 500000 (0)  -> EBDRoayCDDUvDgCimta45ajQeXbexv7aKqJubruqpyvu (noPrivacyWithdraw)
         *  K 10000 (0)   -> 6upXkqkiY3GYBqm3wSReuAsaWxQSY1d67GuRxLhM74Va (tempPrivacyExchange)
         *  K 1000 (0)    -> 6eqAKwBqtAQ28juRdc3429GoRpUTuu86gScJrDN6cqGQ (tempPrivacyExchange)
         *  K 100 (0)     -> BbCteP1N7DiyShnEuCRGkNLeoYbr7v1d5deGDBbeu5Zg (tempPrivacyExchange)
         *  K 10 (0)      -> J5fzggJmRyPwmAcJw7iVD9jG4q4xZyeELNEEjfhKxp4i (tempPrivacyExchange)
         *  Close Dormant -> Gfuc6w9vPwoGKtRwEv7YJtxGWtR4knLGoMoT5Hu1eS6A sending to 8DDrALtni72M6FnCiTMToEssMHDEH3KRP1nhA6svQDxp (closeDormantAccount)
         *  Open          -> 48FpNcnDn5kdFPRjsm5dzr7iXSVBPuF2GcKYbyyrQFD6 (openAccount)
         */
        
        // Ensure all actions have indexes
        intent.actions.enumerated().forEach { index, action in
            XCTAssertEqual(action.id, index)
        }
        
        XCTAssertEqual(intent.actions.count, 10)
        
        try intent.action(at: 0, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000_000)
            XCTAssertEqual(action.destination, organizer.tray.slots[5].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 1, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100_000)
            XCTAssertEqual(action.destination, organizer.tray.slots[4].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 2, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyTransfer)
            XCTAssertEqual(action.amount, 500_000)
            XCTAssertEqual(action.destination, organizer.tray.outgoing.cluster.vaultPublicKey)
        }
        
        try intent.action(at: 3, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10_000)
            XCTAssertEqual(action.destination, organizer.tray.slots[3].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 4, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 1_000)
            XCTAssertEqual(action.destination, organizer.tray.slots[2].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 5, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 100)
            XCTAssertEqual(action.destination, organizer.tray.slots[1].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 6, of: ActionTransfer.self) { action in
            XCTAssertEqual(action.kind, .tempPrivacyExchange)
            XCTAssertEqual(action.amount, 10)
            XCTAssertEqual(action.destination, organizer.tray.slots[0].cluster.vaultPublicKey)
        }
        
        try intent.action(at: 7, of: ActionWithdraw.self) { action in
            XCTAssertEqual(action.kind, .noPrivacyWithdraw(500_000))
            XCTAssertEqual(action.destination, destination)
        }
        
        try intent.action(at: 8, of: ActionOpenAccount.self) { action in
            XCTAssertEqual(action.type, .outgoing)
            XCTAssertEqual(action.owner, resultTray.owner.cluster.authority.keyPair.publicKey)
            XCTAssertEqual(action.accountCluster, resultTray.outgoing.cluster)
        }
        
        try intent.action(at: 9, of: ActionWithdraw.self) { action in
            XCTAssertEqual(action.kind, .closeDormantAccount(.outgoing))
            XCTAssertEqual(action.cluster, resultTray.outgoing.cluster)
            XCTAssertEqual(action.destination, organizer.tray.owner.cluster.vaultPublicKey)
        }
    }
}
