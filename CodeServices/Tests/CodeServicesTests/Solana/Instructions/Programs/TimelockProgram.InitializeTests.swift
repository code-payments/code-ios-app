//
//  TimelockProgram.InitializeTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class TimelockProgram_InitializeTests: XCTestCase {
    
    func testDecode() throws {
        let (transaction, _) = SolanaTransaction.mockTimelockCreateAccount()
        let rawInstruction = transaction.message.instructions[1]
        let instruction = try TimelockProgram.Initialize(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.nonce.base58, "11111111111111111111111111111111")
        XCTAssertEqual(instruction.timelock.base58, "DhvyJ6DsJTUsuhCTy8UzBj4r4nREadG6Cx4HCyiGPQJ1")
        XCTAssertEqual(instruction.vault.base58, "Jy9M4nEwwfeiteamfJ3BN75p45e4tJEaR3xcYh1NtB5")
        XCTAssertEqual(instruction.vaultOwner.base58, "55nFdnZsTaQUEcRiT4CRuTKCduvpDPWf5VKaPpup6Pus")
        XCTAssertEqual(instruction.mint.base58, "kinXdEcpDQeHPEuQnqmUgtYykqKGVFq6CeVX5iAHJq6")
        XCTAssertEqual(instruction.timeAuthority.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.payer.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.lockout, 1814400)
    }
}
