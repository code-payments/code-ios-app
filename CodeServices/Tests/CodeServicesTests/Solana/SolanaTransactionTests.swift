//
//  SolanaTransactionTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class SolanaTransactionTests: XCTestCase {
    
    func testFindInstructions() throws {
        let (transaction, _) = SolanaTransaction.mockCloseDormantAccount()
        
        XCTAssertNotNil(transaction.findInstruction(type: SystemProgram.AdvanceNonce.self))
        XCTAssertNotNil(transaction.findInstruction(type: MemoProgram.Memo.self))
        XCTAssertNotNil(transaction.findInstruction(type: TimelockProgram.RevokeLockWithAuthority.self))
        XCTAssertNotNil(transaction.findInstruction(type: TimelockProgram.DeactivateLock.self))
        XCTAssertNotNil(transaction.findInstruction(type: TimelockProgram.Withdraw.self))
        XCTAssertNotNil(transaction.findInstruction(type: TimelockProgram.CloseAccounts.self))
        
        XCTAssertNil(transaction.findInstruction(type: TimelockProgram.TransferWithAuthority.self))
        XCTAssertNil(transaction.findInstruction(type: TimelockProgram.BurnDustWithAuthority.self))
    }
}
