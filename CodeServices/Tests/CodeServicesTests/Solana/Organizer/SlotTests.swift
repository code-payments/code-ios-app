//
//  SlotTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class SlotTests: XCTestCase {

    private lazy var mnemonic = MnemonicPhrase(words: "couple divorce usage surprise before range feature source bubble chunk spot away".components(separatedBy: " "))!
    
    func testBillCount() {
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
        
        XCTAssertEqual(tray.slots[0].billCount(), 1)
        XCTAssertEqual(tray.slots[1].billCount(), 2)
        XCTAssertEqual(tray.slots[2].billCount(), 3)
        XCTAssertEqual(tray.slots[3].billCount(), 4)
        XCTAssertEqual(tray.slots[4].billCount(), 5)
        XCTAssertEqual(tray.slots[5].billCount(), 6)
        XCTAssertEqual(tray.slots[6].billCount(), 7)
    }
}
