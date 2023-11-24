//
//  TimelockProgram.TransferWithAuthorityTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class TimelockProgram_TransferWithAuthorityTests: XCTestCase {
    
    func testDecode() throws {
        let (transaction, _) = SolanaTransaction.mockTimelockTransfer()
        let rawInstruction = transaction.message.instructions[2]
        let instruction = try TimelockProgram.TransferWithAuthority(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.timelock.base58, "GbhARQ2W8qVgFxE9jSAGTAqeaUuBrczWBd9VvtT5u4MW")
        XCTAssertEqual(instruction.vault.base58, "2khXZy3LDvTxf5VcdgLip11ip4FjTr1vUdq2ATLeQE7r")
        XCTAssertEqual(instruction.vaultOwner.base58, "Ddk7k7zMMWsp8fZB12wqbiADdXKQFWfwUUsxSo73JaQ9")
        XCTAssertEqual(instruction.timeAuthority.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.destination.base58, "2sDAFcEZkLd3mbm6SaZhifctkyB4NWsp94GMnfDs1BfR")
        XCTAssertEqual(instruction.payer.base58, "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")
        XCTAssertEqual(instruction.bump, 255)
        XCTAssertEqual(instruction.kin, 2)
    }
}
