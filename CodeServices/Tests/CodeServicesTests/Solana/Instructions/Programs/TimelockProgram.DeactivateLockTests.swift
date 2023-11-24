//
//  TimelockProgram.DeactivateLockTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class TimelockProgram_DeactivateLockTests: XCTestCase {
    
    func testDecode() throws {
        let (transaction, _) = SolanaTransaction.mockCloseDormantAccount()
        let rawInstruction = transaction.message.instructions[3]
        let instruction = try TimelockProgram.DeactivateLock(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.timelock.base58, "FYo8wnNMXhQNy2pV4cC35ZXspBQ3TaERGKDkzwBvGM4r")
        XCTAssertEqual(instruction.vaultOwner.base58, "Ed3GWPEdMiRXDMf7jU46fRwBF7n6ZZFGN3vH1dYAgME2")
        XCTAssertEqual(instruction.payer.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.bump, 255)
    }
}
