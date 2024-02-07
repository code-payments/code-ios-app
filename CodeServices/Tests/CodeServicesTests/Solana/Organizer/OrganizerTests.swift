//
//  OrganizerTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class OrganizerTests: XCTestCase {
    
    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    private lazy var owner = DerivedKey(path: .solana, keyPair: mnemonic.solanaKeyPair())
    
    func testInit() {
        let organizer = Organizer(mnemonic: mnemonic)
        
        XCTAssertEqual(organizer.tray.owner.cluster, AccountCluster(authority: owner, kind: .timelock))
        
        XCTAssertEqual(organizer.tray.incoming.cluster, AccountCluster(authority: .derive(using: .bucketIncoming(using: 0), mnemonic: mnemonic), kind: .timelock))
        XCTAssertEqual(organizer.tray.outgoing.cluster, AccountCluster(authority: .derive(using: .bucketOutgoing(using: 0), mnemonic: mnemonic), kind: .timelock))
        
        XCTAssertEqual(organizer.tray.slots.count, 7)
        XCTAssertEqual(organizer.tray.slots, [
            Slot(type: .bucket1,    mnemonic: mnemonic),
            Slot(type: .bucket10,   mnemonic: mnemonic),
            Slot(type: .bucket100,  mnemonic: mnemonic),
            Slot(type: .bucket1k,   mnemonic: mnemonic),
            Slot(type: .bucket10k,  mnemonic: mnemonic),
            Slot(type: .bucket100k, mnemonic: mnemonic),
            Slot(type: .bucket1m,   mnemonic: mnemonic),
        ])
    }
    
    func testAllAccounts() {
        let organizer = Organizer(mnemonic: mnemonic)
        
        let accounts = organizer.allAccounts()
        
        XCTAssertEqual(accounts.count, 10)
        XCTAssertEqual(accounts.count, 3 + SlotType.allCases.count)
        
        XCTAssertEqual(accounts.filter { $0.type == .primary }.count,             1)
        XCTAssertEqual(accounts.filter { $0.type == .incoming }.count,            1)
        XCTAssertEqual(accounts.filter { $0.type == .outgoing }.count,            1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket1) }.count,    1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket10) }.count,   1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket100) }.count,  1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket1k) }.count,   1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket10k) }.count,  1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket100k) }.count, 1)
        XCTAssertEqual(accounts.filter { $0.type == .bucket(.bucket1m) }.count,   1)
    }
    
    func testAccountCluster() {
        let cluster = AccountCluster(authority: owner, kind: .timelock)
        let timelockAccounts = TimelockDerivedAccounts(owner: owner.keyPair.publicKey)
        
        XCTAssertEqual(cluster.authority, owner)
        XCTAssertEqual(cluster.timelock, timelockAccounts)
    }
    
    func testUnlockedState() {
        let organizer = Organizer(mnemonic: mnemonic)
        
        XCTAssertFalse(organizer.isUnuseable)
        
        AccountInfo.ManagementState.allCases.forEach { state in
            organizer.setAccountInfo([
                organizer.primaryVault: AccountInfo(
                    index: 0,
                    accountType: .primary,
                    address: organizer.primaryVault,
                    owner: nil,
                    authority: nil,
                    balanceSource: .blockchain,
                    balance: 15,
                    managementState: state,
                    blockchainState: .exists,
                    claimState: .unknown,
                    mustRotate: false,
                    originalKinAmount: nil,
                    relationship: nil
                )
            ])
            
            if state == .locked {
                XCTAssertFalse(organizer.isUnuseable)
            } else {
                XCTAssertTrue(organizer.isUnuseable)
            }
        }
    }
}
