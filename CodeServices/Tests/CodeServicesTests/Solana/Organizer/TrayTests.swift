//
//  TrayTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class TrayTests: XCTestCase {

    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    
    // MARK: - Slots -
    
    func testSlotsUp() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(2) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(3) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(4) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(5) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(6) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(7) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotUp(from: .bucket1)?.type,    .bucket10)
        XCTAssertEqual(tray.slotUp(from: .bucket10)?.type,   .bucket100)
        XCTAssertEqual(tray.slotUp(from: .bucket100)?.type,  .bucket1k)
        XCTAssertEqual(tray.slotUp(from: .bucket1k)?.type,   .bucket10k)
        XCTAssertEqual(tray.slotUp(from: .bucket10k)?.type,  .bucket100k)
        XCTAssertEqual(tray.slotUp(from: .bucket100k)?.type, .bucket1m)
        XCTAssertEqual(tray.slotUp(from: .bucket1m)?.type,   nil)
    }
    
    func testSlotsDown() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(2) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(3) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(4) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(5) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(6) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(7) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotDown(from: .bucket1)?.type,    nil)
        XCTAssertEqual(tray.slotDown(from: .bucket10)?.type,   .bucket1)
        XCTAssertEqual(tray.slotDown(from: .bucket100)?.type,  .bucket10)
        XCTAssertEqual(tray.slotDown(from: .bucket1k)?.type,   .bucket100)
        XCTAssertEqual(tray.slotDown(from: .bucket10k)?.type,  .bucket1k)
        XCTAssertEqual(tray.slotDown(from: .bucket100k)?.type, .bucket10k)
        XCTAssertEqual(tray.slotDown(from: .bucket1m)?.type,   .bucket100k)
    }
    
    // MARK: - Balance -
    
    func testSetBalances() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(2) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(3) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(4) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(5) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(6) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(7) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slots.count, 7)
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    Kin(1) * SlotType.bucket1.billValue)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   Kin(2) * SlotType.bucket10.billValue)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  Kin(3) * SlotType.bucket100.billValue)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   Kin(4) * SlotType.bucket1k.billValue)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  Kin(5) * SlotType.bucket10k.billValue)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, Kin(6) * SlotType.bucket100k.billValue)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   Kin(7) * SlotType.bucket1m.billValue)
        
        tray.setBalances([
            .bucket(.bucket10k): Kin(7) * SlotType.bucket10k.billValue,
        ])
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    Kin(1) * SlotType.bucket1.billValue)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   Kin(2) * SlotType.bucket10.billValue)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  Kin(3) * SlotType.bucket100.billValue)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   Kin(4) * SlotType.bucket1k.billValue)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  Kin(7) * SlotType.bucket10k.billValue)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, Kin(6) * SlotType.bucket100k.billValue)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   Kin(7) * SlotType.bucket1m.billValue)
    }
    
    func testSetPartialBalances() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(9) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(9) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(9) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(9) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(9) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(9) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(9) * SlotType.bucket1m.billValue,
        ])
    }
    
    func testBalance() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(3) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(0) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(0) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(0) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(0) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(0) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotsBalance, 3)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(0) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(0) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(0) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(4) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(0) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(0) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotsBalance, 4_000)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(0) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(0) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(0) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(0) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(0) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(0) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(5) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotsBalance, 5_000_000)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(2) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(3) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(4) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(5) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(6) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(7) * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotsBalance, Kin(kin: 7_654_321))
    }
    
    // MARK: - Exchange (Large -> Small) -
    
    func testExchangeLargeToSmallFull() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(1) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(1) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(1) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(1) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(1) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(1) * SlotType.bucket1m.billValue,
        ])
        
        let exchanges = tray.exchangeLargeToSmall()
        
        XCTAssertEqual(exchanges.count, 6)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1m),   to: .bucket(.bucket100k), kin: 1_000_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket10k),  kin: 100_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),   kin: 10_000))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket100),  kin: 1_000))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .bucket(.bucket100),  to: .bucket(.bucket10),   kin: 100))
        XCTAssertEqual(exchanges[5], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket1),    kin: 10))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    11)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   100)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  1_000)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   10_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  100_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 1_000_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testExchangeLargeToSmallLargestBillOnly() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(0) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(0) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(0) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(0) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(0) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(0) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(1) * SlotType.bucket1m.billValue,
        ])
        
        let exchanges = tray.exchangeLargeToSmall()
        
        XCTAssertEqual(exchanges.count, 6)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1m),   to: .bucket(.bucket100k), kin: 1_000_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket10k),  kin: 100_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),   kin: 10_000))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket100),  kin: 1_000))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .bucket(.bucket100),  to: .bucket(.bucket10),   kin: 100))
        XCTAssertEqual(exchanges[5], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket1),    kin: 10))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testExchangeLargeToSmallLargestBillOverflowing() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1m): Kin(20) * SlotType.bucket1m.billValue,
        ])
        
        let exchanges = tray.exchangeLargeToSmall()
        
        XCTAssertEqual(exchanges.count, 6)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1m),   to: .bucket(.bucket100k), kin: 1_000_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket10k),  kin: 100_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),   kin: 10_000))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket100),  kin: 1_000))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .bucket(.bucket100),  to: .bucket(.bucket10),   kin: 100))
        XCTAssertEqual(exchanges[5], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket1),    kin: 10))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   19_000_000)
    }
    
    // MARK: - Exchange (Small -> Large) -
    
    func testExchangeSmallToLargeSmallestBillOnly() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1): 1_000_000,
        ])
        
        let exchanges = tray.exchangeSmallToLarge()
        
        XCTAssertEqual(exchanges.count, 15)
        
        XCTAssertEqual(exchanges[0],  InternalExchange(from: .bucket(.bucket1),   to: .bucket(.bucket10),   kin: 900_000))
        XCTAssertEqual(exchanges[1],  InternalExchange(from: .bucket(.bucket1),   to: .bucket(.bucket10),   kin: 90_000))
        XCTAssertEqual(exchanges[2],  InternalExchange(from: .bucket(.bucket1),   to: .bucket(.bucket10),   kin: 9_000))
        XCTAssertEqual(exchanges[3],  InternalExchange(from: .bucket(.bucket1),   to: .bucket(.bucket10),   kin: 900))
        XCTAssertEqual(exchanges[4],  InternalExchange(from: .bucket(.bucket1),   to: .bucket(.bucket10),   kin: 90))
        
        XCTAssertEqual(exchanges[5],  InternalExchange(from: .bucket(.bucket10),  to: .bucket(.bucket100),  kin: 900_000))
        XCTAssertEqual(exchanges[6],  InternalExchange(from: .bucket(.bucket10),  to: .bucket(.bucket100),  kin: 90_000))
        XCTAssertEqual(exchanges[7],  InternalExchange(from: .bucket(.bucket10),  to: .bucket(.bucket100),  kin: 9_000))
        XCTAssertEqual(exchanges[8],  InternalExchange(from: .bucket(.bucket10),  to: .bucket(.bucket100),  kin: 900))
        
        XCTAssertEqual(exchanges[9],  InternalExchange(from: .bucket(.bucket100), to: .bucket(.bucket1k),   kin: 900_000))
        XCTAssertEqual(exchanges[10], InternalExchange(from: .bucket(.bucket100), to: .bucket(.bucket1k),   kin: 90_000))
        XCTAssertEqual(exchanges[11], InternalExchange(from: .bucket(.bucket100), to: .bucket(.bucket1k),   kin: 9_000))
        
        XCTAssertEqual(exchanges[12], InternalExchange(from: .bucket(.bucket1k),  to: .bucket(.bucket10k),  kin: 900_000))
        XCTAssertEqual(exchanges[13], InternalExchange(from: .bucket(.bucket1k),  to: .bucket(.bucket10k),  kin: 90_000))
        
        XCTAssertEqual(exchanges[14], InternalExchange(from: .bucket(.bucket10k), to: .bucket(.bucket100k), kin: 900_000))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testExchangeSmallToLarge1000() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1k): 1_000_000,
        ])
        
        let exchanges = tray.exchangeSmallToLarge()
        
        XCTAssertEqual(exchanges.count, 3)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1k),  to: .bucket(.bucket10k),  kin: 900_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket1k),  to: .bucket(.bucket10k),  kin: 90_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket10k), to: .bucket(.bucket100k), kin: 900_000))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   10_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    // MARK: - Redistribute -
    
    func testRedistributeFromMiddle() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket10k): 1_000_000,
        ])
        
        let exchanges = tray.redistribute()
        
        XCTAssertEqual(exchanges.count, 5)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),   kin: 10_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket100),  kin: 1_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket100),  to: .bucket(.bucket10),   kin: 100))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket1),    kin: 10))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket100k), kin: 900_000))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testRedistributeFull() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(19) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(28) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(16) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(39) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(42) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(17) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(1) * SlotType.bucket1m.billValue,
        ])
        
        let exchanges = tray.redistribute()
        
        XCTAssertEqual(exchanges.count, 5)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1),    to: .bucket(.bucket10),   kin: 10))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket100),  kin: 200))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket10k),  kin: 30_000))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket100k), kin: 300_000))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket1m),   kin: 1_000_000))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    9)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  1_800)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  150_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 1_000_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   2_000_000)
    }
    
    func testRedistributeFullWithGap() {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(19) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(28) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(16) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(0) * SlotType.bucket1k.billValue, // Gap
            .bucket(.bucket10k):  Kin(42) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(17) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(1) * SlotType.bucket1m.billValue,
        ])
        
        let exchanges = tray.redistribute()
        
        XCTAssertEqual(exchanges.count, 5)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),   kin: 10_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket1),    to: .bucket(.bucket10),   kin: 10))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket100),  kin: 200))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket100k), kin: 300_000))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket1m),   kin: 1_000_000))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    9)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  1_800)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   10_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  110_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 1_000_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   2_000_000)
    }
    
    // MARK: - Normalize -
    
    func testNormalize() {
        let tray = Tray(mnemonic: mnemonic)
        
        let cases: [(SlotType, Kin, [Kin])] = [
            (.bucket1k,  5000, [5000]),
            (.bucket1k,   500, []),
            (.bucket1k,     0, []),
            (.bucket100, 1200, [900, 300]),
            (.bucket100, 1050, [900, 100]),
            (.bucket1,     20, [9, 9, 2]),
        ]
        
        cases.forEach { slotType, kin, expectation in
            var amounts: [Kin] = []
            tray.normalize(slotType: slotType, amount: kin) { iterationAmount in
                amounts.append(iterationAmount)
            }
            XCTAssertEqual(amounts, expectation)
        }
    }
    
    func testNormalizeLargest() throws {
        let tray = Tray(mnemonic: mnemonic)
        
        let cases: [(Kin, [Kin])] = [
            (1_489_725, [
                1_000_000,
                400_000,
                80_000,
                9_000,
                700,
                20,
                5,
            ]),
            (10_893_257, [
                9_000_000,
                1_000_000,
                800_000,
                90_000,
                3_000,
                200,
                50,
                7,
            ]),
            (500_000, [
                500_000,
            ]),
            (950_204, [
                900_000,
                50_000,
                200,
                4,
            ]),
            (30_852, [
                30_000,
                800,
                50,
                2,
            ]),
        ]
        
        cases.forEach { kin, expectation in
            var amounts: [Kin] = []
            tray.normalizeLargest(amount: kin) { iterationAmount in
                amounts.append(iterationAmount)
            }
            XCTAssertEqual(amounts, expectation)
        }
    }
    
    // MARK: - Transfer (Naive) -
    
    func testNaiveTransfer() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(10) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(9)  * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(19) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(8)  * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(9)  * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(9)  * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0)  * SlotType.bucket1m.billValue,
        ])
        
        let exchanges = try tray.transfer(amount: 9_000)
        
        XCTAssertEqual(exchanges.count, 3)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1k),  to: .outgoing, kin: 8_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 900))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 100))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    10)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   90)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  900)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
        
        XCTAssertEqual(tray.slotsBalance, 991_000)
        XCTAssertEqual(tray.outgoing.partialBalance, 9_000)
    }
    
    func testNaiveTransferInsufficientBalance() {
        var tray = Tray(mnemonic: mnemonic)
        
        XCTAssertError(Tray.Error.self, error: .insufficientTrayBalance) {
            let _ = try tray.transfer(amount: 900)
        }
    }
    
    // MARK: - Transfer (Dynamic Steps) -
    
    func testDynamicWithdrawalStep1GreaterThan() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1)  * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(1)  * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(1)  * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(1)  * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(10) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(9)  * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0)  * SlotType.bucket1m.billValue,
        ])
        
        let step = try tray.withdrawDynamicallyStep1(amount: 111)
        
        XCTAssertEqual(step.remaining, 0)
        XCTAssertEqual(step.index, 3)
        
        let exchanges = step.exchanges
        
        XCTAssertEqual(exchanges.count, 3)
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1),   to: .outgoing, kin: 1))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket10),  to: .outgoing, kin: 10))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 100))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   1_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  100_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testDynamicWithdrawalStep1LessThan() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1)  * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(1)  * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(1)  * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(1)  * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(10) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(9)  * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0)  * SlotType.bucket1m.billValue,
        ])
        
        let step = try tray.withdrawDynamicallyStep1(amount: 9_000)
        
        XCTAssertEqual(step.remaining, 7_889)
        XCTAssertEqual(step.index, 4)
        
        let exchanges = step.exchanges
        
        XCTAssertEqual(exchanges.count, 4)
        XCTAssertEqual(exchanges[0], InternalExchange(from: .bucket(.bucket1),   to: .outgoing, kin: 1))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .bucket(.bucket10),  to: .outgoing, kin: 10))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 100))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .bucket(.bucket1k),  to: .outgoing, kin: 1_000))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  100_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testDynamicWithdrawalStep2() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1)  * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(1)  * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(1)  * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(1)  * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(10) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(9)  * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0)  * SlotType.bucket1m.billValue,
        ])
        
        let step = try tray.withdrawDynamicallyStep1(amount: 9_000)
        
        XCTAssertEqual(step.remaining, 7_889)
        XCTAssertEqual(step.exchanges.totalAmount(), 1_111)
        XCTAssertEqual(step.index, 4)
        
        let finalExchanges = try tray.withdrawDynamicallyStep2(step: step)
        let exchanges = step.exchanges + finalExchanges
        
        XCTAssertEqual(exchanges.count, 12)
        
        XCTAssertEqual(exchanges[0],  InternalExchange(from: .bucket(.bucket1),   to: .outgoing, kin: 1))
        XCTAssertEqual(exchanges[1],  InternalExchange(from: .bucket(.bucket10),  to: .outgoing, kin: 10))
        XCTAssertEqual(exchanges[2],  InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 100))
        XCTAssertEqual(exchanges[3],  InternalExchange(from: .bucket(.bucket1k),  to: .outgoing, kin: 1_000))
            
        XCTAssertEqual(exchanges[4],  InternalExchange(from: .bucket(.bucket10k), to: .bucket(.bucket1k),  kin: 10_000))
        XCTAssertEqual(exchanges[5],  InternalExchange(from: .bucket(.bucket1k),  to: .bucket(.bucket100), kin: 1_000))
        XCTAssertEqual(exchanges[6],  InternalExchange(from: .bucket(.bucket1k),  to: .outgoing,           kin: 7_000))
        XCTAssertEqual(exchanges[7],  InternalExchange(from: .bucket(.bucket100), to: .bucket(.bucket10),  kin: 100))
        XCTAssertEqual(exchanges[8],  InternalExchange(from: .bucket(.bucket100), to: .outgoing,           kin: 800))
        XCTAssertEqual(exchanges[9],  InternalExchange(from: .bucket(.bucket10),  to: .bucket(.bucket1),   kin: 10))
        XCTAssertEqual(exchanges[10], InternalExchange(from: .bucket(.bucket10),  to: .outgoing,           kin: 80))
        XCTAssertEqual(exchanges[11], InternalExchange(from: .bucket(.bucket1),   to: .outgoing,           kin: 9))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    1)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   10)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  100)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   2_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
    }
    
    func testDynamicWithdrawalStep2InvalidIndex() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        // Too low
        do {
            let step = InternalDynamicStep(
                remaining: 0,
                index: 0,
                exchanges: []
            )
            let results = try tray.withdrawDynamicallyStep2(step: step)
            XCTAssertEqual(results, [])
        }
        
        // Too high
        do {
            let step = InternalDynamicStep(
                remaining: 0,
                index: 9,
                exchanges: []
            )
            let results = try tray.withdrawDynamicallyStep2(step: step)
            XCTAssertEqual(results, [])
        }
    }
    
    func testDynamicWithdrawalStep2NoRemaining() throws {
        var tray = Tray(mnemonic: mnemonic)
        let step = InternalDynamicStep(
            remaining: 0,
            index: 2,
            exchanges: []
        )
        
        let exchanges = try tray.withdrawDynamicallyStep2(step: step)
        
        XCTAssertEqual(exchanges, [])
    }
    
    // MARK: - Transfer (Dynamic) -
    
    func testDynamicWithdrawalAndRedistribute() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(1)  * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(1)  * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(1)  * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(1)  * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(10) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(9)  * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0)  * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotsBalance, 1_001_111)
        XCTAssertEqual(tray.outgoing.partialBalance, 0)
        
        let exchanges = try tray.transfer(amount: 9_000)
        
        XCTAssertEqual(exchanges.count, 12)
        
        XCTAssertEqual(exchanges[0],  InternalExchange(from: .bucket(.bucket1),   to: .outgoing, kin: 1))
        XCTAssertEqual(exchanges[1],  InternalExchange(from: .bucket(.bucket10),  to: .outgoing, kin: 10))
        XCTAssertEqual(exchanges[2],  InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 100))
        XCTAssertEqual(exchanges[3],  InternalExchange(from: .bucket(.bucket1k),  to: .outgoing, kin: 1_000))
        
        XCTAssertEqual(exchanges[4],  InternalExchange(from: .bucket(.bucket10k), to: .bucket(.bucket1k),  kin: 10_000))
        XCTAssertEqual(exchanges[5],  InternalExchange(from: .bucket(.bucket1k),  to: .bucket(.bucket100), kin: 1_000))
        XCTAssertEqual(exchanges[6],  InternalExchange(from: .bucket(.bucket1k),  to: .outgoing,           kin: 7_000))
        XCTAssertEqual(exchanges[7],  InternalExchange(from: .bucket(.bucket100), to: .bucket(.bucket10),  kin: 100))
        XCTAssertEqual(exchanges[8],  InternalExchange(from: .bucket(.bucket100), to: .outgoing,           kin: 800))
        XCTAssertEqual(exchanges[9],  InternalExchange(from: .bucket(.bucket10),  to: .bucket(.bucket1),   kin: 10))
        XCTAssertEqual(exchanges[10], InternalExchange(from: .bucket(.bucket10),  to: .outgoing,           kin: 80))
        XCTAssertEqual(exchanges[11], InternalExchange(from: .bucket(.bucket1),   to: .outgoing,           kin: 9))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    1)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   10)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  100)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   2_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  90_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 900_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
        
        XCTAssertEqual(tray.slotsBalance, 992_111)
        XCTAssertEqual(tray.outgoing.partialBalance, 9_000)
        
        let redistributions = tray.redistribute()
        
        XCTAssertEqual(redistributions.count, 5)
        
        XCTAssertEqual(redistributions[0], InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),  kin: 10_000))
        XCTAssertEqual(redistributions[1], InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket10k), kin: 100_000))
        XCTAssertEqual(redistributions[2], InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket100), kin: 1_000))
        XCTAssertEqual(redistributions[3], InternalExchange(from: .bucket(.bucket100),  to: .bucket(.bucket10),  kin: 100))
        XCTAssertEqual(redistributions[4], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket1),   kin: 10))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    11)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   100)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  1_000)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   11_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  180_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 800_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
        
        XCTAssertEqual(tray.slotsBalance, 992_111)
        XCTAssertEqual(tray.outgoing.partialBalance, 9_000)
    }
    
    func testDynamicWithdrawalExample1() throws {
        var tray = Tray(mnemonic: mnemonic)
        
        tray.setBalances([
            .bucket(.bucket1):    Kin(13) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(15) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(10) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(5)  * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(0)  * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(0)  * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(0)  * SlotType.bucket1m.billValue,
        ])
        
        XCTAssertEqual(tray.slotsBalance, 6_163)
        XCTAssertEqual(tray.outgoing.partialBalance, 0)
        
        let exchanges = try tray.transfer(amount: 6_000) // Should use naive strategy (no exchanges below)
        
        XCTAssertEqual(exchanges.count, 3)
        
        XCTAssertEqual(exchanges[0],  InternalExchange(from: .bucket(.bucket1k),  to: .outgoing, kin: 5_000))
        XCTAssertEqual(exchanges[1],  InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 900))
        XCTAssertEqual(exchanges[2],  InternalExchange(from: .bucket(.bucket100), to: .outgoing, kin: 100))
        
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    13)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   150)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 0)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   0)
        
        XCTAssertEqual(tray.slotsBalance, 163)
        XCTAssertEqual(tray.outgoing.partialBalance, 6_000)
    }
    
    func testDynamicWithdrawalExample2() throws {
        var tray = Tray(mnemonic: mnemonic)

        tray.setBalances([
            .bucket(.bucket1):    Kin(0) * SlotType.bucket1.billValue,
            .bucket(.bucket10):   Kin(4) * SlotType.bucket10.billValue,
            .bucket(.bucket100):  Kin(1) * SlotType.bucket100.billValue,
            .bucket(.bucket1k):   Kin(9) * SlotType.bucket1k.billValue,
            .bucket(.bucket10k):  Kin(1) * SlotType.bucket10k.billValue,
            .bucket(.bucket100k): Kin(6) * SlotType.bucket100k.billValue,
            .bucket(.bucket1m):   Kin(1) * SlotType.bucket1m.billValue,
        ])

        XCTAssertEqual(tray.slotsBalance, 1_619_140)
        XCTAssertEqual(tray.outgoing.partialBalance, 0)

        let exchanges = try tray.transfer(amount: 359_804)
        
        XCTAssertEqual(exchanges.count, 14)

        XCTAssertEqual(exchanges[0],  InternalExchange(from: .bucket(.bucket10),   to: .outgoing,           kin: 40))
        XCTAssertEqual(exchanges[1],  InternalExchange(from: .bucket(.bucket100),  to: .outgoing,           kin: 100))
        XCTAssertEqual(exchanges[2],  InternalExchange(from: .bucket(.bucket1k),   to: .outgoing,           kin: 9_000))
        XCTAssertEqual(exchanges[3],  InternalExchange(from: .bucket(.bucket10k),  to: .outgoing,           kin: 10_000))
        XCTAssertEqual(exchanges[4],  InternalExchange(from: .bucket(.bucket100k), to: .outgoing,           kin: 300_000))
        XCTAssertEqual(exchanges[5],  InternalExchange(from: .bucket(.bucket100k), to: .bucket(.bucket10k), kin: 100_000))
        XCTAssertEqual(exchanges[6],  InternalExchange(from: .bucket(.bucket10k),  to: .bucket(.bucket1k),  kin: 10_000))
        XCTAssertEqual(exchanges[7],  InternalExchange(from: .bucket(.bucket10k),  to: .outgoing,           kin: 40_000))
        XCTAssertEqual(exchanges[8],  InternalExchange(from: .bucket(.bucket1k),   to: .bucket(.bucket100), kin: 1_000))
        XCTAssertEqual(exchanges[9],  InternalExchange(from: .bucket(.bucket100),  to: .bucket(.bucket10),  kin: 100))
        XCTAssertEqual(exchanges[10], InternalExchange(from: .bucket(.bucket100),  to: .outgoing,           kin: 600))
        XCTAssertEqual(exchanges[11], InternalExchange(from: .bucket(.bucket10),   to: .bucket(.bucket1),   kin: 10))
        XCTAssertEqual(exchanges[12], InternalExchange(from: .bucket(.bucket10),   to: .outgoing,           kin: 60))
        XCTAssertEqual(exchanges[13], InternalExchange(from: .bucket(.bucket1),    to: .outgoing,           kin: 4))

        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    6)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   30)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  300)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   9_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  50_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 200_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   1_000_000)

        XCTAssertEqual(tray.slotsBalance, 1_259_336)
        XCTAssertEqual(tray.outgoing.partialBalance, 359_804)
    }
    
    func _testDynamicWithdrawalRandom() throws {
        
        let randomKin: () -> Kin = {
            let bills = UInt64.random(in: 0...10)
            return Kin(kin: bills)
        }
        
        var tray = Tray(mnemonic: mnemonic)
        let cleanTray = tray
        
        for i in 0..<1_000_000 {
            let balances: [AccountType: Kin] = [
                .bucket(.bucket1):    randomKin() * SlotType.bucket1.billValue,
                .bucket(.bucket10):   randomKin() * SlotType.bucket10.billValue,
                .bucket(.bucket100):  randomKin() * SlotType.bucket100.billValue,
                .bucket(.bucket1k):   randomKin() * SlotType.bucket1k.billValue,
                .bucket(.bucket10k):  randomKin() * SlotType.bucket10k.billValue,
                .bucket(.bucket100k): randomKin() * SlotType.bucket100k.billValue,
                .bucket(.bucket1m):   randomKin() * SlotType.bucket1m.billValue,
            ]
            
            for _ in 0..<100 {
                tray = cleanTray
                tray.setBalances(balances)
                
                let balance = tray.slotsBalance.truncatedKinValue
                let toWithdraw = Kin(kin: .random(in: 1...balance))
                let trayState = tray
                do {
                    _ = try tray.withdrawDynamically(amount: toWithdraw)
                } catch {
                    trayState.prettyPrinted()
                    print("Error: \(error)")
                    print("Withdrawing: \(toWithdraw.description)")
                }
            }
            
            print("Count: \(i)")
        }
    }
    
    // MARK: - Permutations -
    
    func testTransferAllPermutations() throws {
        var count = 0
        
        var tray = Tray(mnemonic: mnemonic)
        let cleanTray = tray
        
        var a = 0
        var b = 0
        var c = 0
        var d = 0
        var e = 0
        var f = 0
        var g = 0
        
        for i in 1...1000 {
            
            a = (i / 1) % 10       // <1s
            b = (i / 10) % 10      // <1s
            c = (i / 100) % 10     // ~16 sec
            d = (i / 1000) % 10    // ~28 min
            e = (i / 10000) % 10   // ~48 hours
            f = (i / 100000) % 10  // Too long
            g = (i / 1000000) % 10 // Too long
            
            let balances: [AccountType: Kin] = [
                .bucket(.bucket1):    Kin(kin: a)! * SlotType.bucket1.billValue,
                .bucket(.bucket10):   Kin(kin: b)! * SlotType.bucket10.billValue,
                .bucket(.bucket100):  Kin(kin: c)! * SlotType.bucket100.billValue,
                .bucket(.bucket1k):   Kin(kin: d)! * SlotType.bucket1k.billValue,
                .bucket(.bucket10k):  Kin(kin: e)! * SlotType.bucket10k.billValue,
                .bucket(.bucket100k): Kin(kin: f)! * SlotType.bucket100k.billValue,
                .bucket(.bucket1m):   Kin(kin: g)! * SlotType.bucket1m.billValue,
            ]
            
            tray = cleanTray
            tray.setBalances(balances)
            
            for amount in 0..<tray.slotsBalance.truncatedKinValue {
                tray = cleanTray
                tray.setBalances(balances)
                
                let toWithdraw = Kin(kin: amount + 1)
                do {
                    count += 1
//                    let exchanges = try tray.transfer(amount: toWithdraw)
                    let exchanges = try tray.withdrawDynamically(amount: toWithdraw)
                    let total = exchanges.reduce(into: 0 as UInt64) { partialResult, exchange in
                        if exchange.to == .outgoing {
                            partialResult += exchange.kin.truncatedKinValue
                        }
                    }
                    XCTAssertEqual(total, toWithdraw.truncatedKinValue)
                } catch {
                    print("Error: \(error)")
                    print("Withdrawing: \(toWithdraw.description)")
                }
            }
        }
        
        print("Total invocation count: \(count)")
    }
    
    // MARK: - Receive -
    
    func testReceiveSingleSlot() throws {
        var tray = Tray(mnemonic: mnemonic)
        let amount = 1_000_000 as Kin
        
        try tray.increment(.incoming, kin: 1_000_000)
        let exchanges = try tray.receive(from: .incoming, amount: 1_000_000)
        
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertEqual(exchanges[0], InternalExchange(from: .incoming, to: .bucket(.bucket1m), kin: amount))
        
        XCTAssertEqual(tray.incoming.partialBalance,               0)
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 0)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   1_000_000)
    }
    
    func testReceiveAllSlots() throws {
        var tray = Tray(mnemonic: mnemonic)
        let amount = 1_234_567 as Kin
        
        try tray.increment(.incoming, kin: amount)
        let exchanges = try tray.receive(from: .incoming, amount: amount)
        
        XCTAssertEqual(exchanges.count, 7)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 1_000_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .incoming, to: .bucket(.bucket100k), kin: 200_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .incoming, to: .bucket(.bucket10k),  kin: 30_000))
        XCTAssertEqual(exchanges[3], InternalExchange(from: .incoming, to: .bucket(.bucket1k),   kin: 4_000))
        XCTAssertEqual(exchanges[4], InternalExchange(from: .incoming, to: .bucket(.bucket100),  kin: 500))
        XCTAssertEqual(exchanges[5], InternalExchange(from: .incoming, to: .bucket(.bucket10),   kin: 60))
        XCTAssertEqual(exchanges[6], InternalExchange(from: .incoming, to: .bucket(.bucket1),    kin: 7))
        
        XCTAssertEqual(tray.incoming.partialBalance,               0)
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    7)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   60)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  500)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   4_000)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  30_000)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 200_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   1_000_000)
    }
    
    func testReceiveThreeSlots() throws {
        var tray = Tray(mnemonic: mnemonic)
        let amount = 1_200_500 as Kin
        
        try tray.increment(.incoming, kin: amount)
        let exchanges = try tray.receive(from: .incoming, amount: amount)
        
        XCTAssertEqual(exchanges.count, 3)
        
        XCTAssertEqual(exchanges[0], InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 1_000_000))
        XCTAssertEqual(exchanges[1], InternalExchange(from: .incoming, to: .bucket(.bucket100k), kin: 200_000))
        XCTAssertEqual(exchanges[2], InternalExchange(from: .incoming, to: .bucket(.bucket100),  kin: 500))
        
        XCTAssertEqual(tray.incoming.partialBalance,               0)
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    0)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  500)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 200_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   1_000_000)
    }
    
    func testReceiveLargeAmounts() throws {
        var tray = Tray(mnemonic: mnemonic)
        let amount = 95_800_173 as Kin
        
        try tray.increment(.incoming, kin: amount)
        let exchanges = try tray.receive(from: .incoming, amount: amount)
        
        XCTAssertEqual(exchanges.count, 15)
        
        XCTAssertEqual(exchanges[0],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[1],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[2],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[3],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[4],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[5],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[6],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[7],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[8],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[9],  InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 9_000_000))
        XCTAssertEqual(exchanges[10], InternalExchange(from: .incoming, to: .bucket(.bucket1m),   kin: 5_000_000))
        XCTAssertEqual(exchanges[11], InternalExchange(from: .incoming, to: .bucket(.bucket100k), kin: 800_000))
        XCTAssertEqual(exchanges[12], InternalExchange(from: .incoming, to: .bucket(.bucket100),  kin: 100))
        XCTAssertEqual(exchanges[13], InternalExchange(from: .incoming, to: .bucket(.bucket10),   kin: 70))
        XCTAssertEqual(exchanges[14], InternalExchange(from: .incoming, to: .bucket(.bucket1),    kin: 3))
        
        XCTAssertEqual(tray.incoming.partialBalance,               0)
        XCTAssertEqual(tray.slot(for: .bucket1).partialBalance,    3)
        XCTAssertEqual(tray.slot(for: .bucket10).partialBalance,   70)
        XCTAssertEqual(tray.slot(for: .bucket100).partialBalance,  100)
        XCTAssertEqual(tray.slot(for: .bucket1k).partialBalance,   0)
        XCTAssertEqual(tray.slot(for: .bucket10k).partialBalance,  0)
        XCTAssertEqual(tray.slot(for: .bucket100k).partialBalance, 800_000)
        XCTAssertEqual(tray.slot(for: .bucket1m).partialBalance,   95_000_000)
    }
    
    func testReceiveInsufficientBalance() {
        var tray = Tray(mnemonic: mnemonic)
        
        XCTAssertError(Tray.Error.self, error: .invalidSlotBalance) {
            _ = try tray.receive(from: .incoming, amount: 100)
        }
    }
}

extension Array where Element == InternalExchange {
    func totalAmount() -> Kin {
        reduce(into: 0 as Kin) { result, exchange in
            result = result + exchange.kin
        }
    }
}

extension Array where Element == InternalExchange {
    func prettyPrinted() -> [String] {
        map {
            if let destination = $0.to {
                return "(\($0.from) -> \(destination)) - \($0.kin)"
            } else {
                return "\($0.from) -> \($0.kin)"
            }
        }
    }
}
