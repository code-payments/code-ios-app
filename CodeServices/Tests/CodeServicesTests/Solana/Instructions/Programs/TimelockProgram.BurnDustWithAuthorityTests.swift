//
//  TimelockProgram.BurnDustWithAuthorityTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class TimelockProgram_BurnDustWithAuthorityTests: XCTestCase {
    
    func testDecode() throws {
        let (transaction, _) = SolanaTransaction.mockCloseEmptyAccount()
        let rawInstruction = transaction.message.instructions[1]
        let instruction = try TimelockProgram.BurnDustWithAuthority(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.timelock.base58, "HzjXkhAQTEffQfXVwCW3yYJ6RbbJToXEDjnfaFZg7e9R")
        XCTAssertEqual(instruction.vault.base58, "8V9ioABwqNLsidtRdSWqjJZPxqzKCh6vVqxZWxoSVMb")
        XCTAssertEqual(instruction.vaultOwner.base58, "CiMF8M1VD8HYbWHoX3BhKk4XDcLgzpvz4QJsdULWU84")
        XCTAssertEqual(instruction.timeAuthority.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.mint.base58, "kinXdEcpDQeHPEuQnqmUgtYykqKGVFq6CeVX5iAHJq6")
        XCTAssertEqual(instruction.payer.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.bump, 255)
        XCTAssertEqual(instruction.maxAmount, 1)
    }
}
