//
//  TimelockProgram.RevokeLockWithAuthorityTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class TimelockProgram_RevokeLockWithAuthorityTests: XCTestCase {
    
    func testDecode() throws {
        let (transaction, _) = SolanaTransaction.mockCloseDormantAccount()
        let rawInstruction = transaction.message.instructions[2]
        let instruction = try TimelockProgram.RevokeLockWithAuthority(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.timelock.base58, "FYo8wnNMXhQNy2pV4cC35ZXspBQ3TaERGKDkzwBvGM4r")
        XCTAssertEqual(instruction.vault.base58, "EKTfBuyKkhPcvzM7rzKVNCxfj5qeiUwVYLtSrB5XQZ4d")
        XCTAssertEqual(instruction.closeAuthority.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.payer.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.bump, 255)
    }
}
