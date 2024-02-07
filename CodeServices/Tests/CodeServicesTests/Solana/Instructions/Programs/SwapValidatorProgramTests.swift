//
//  SwapValidatorProgramTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class SwapValidatorProgramTests: XCTestCase {
    
    func testDecodePreSwap() throws {
        let (transaction, _) = SolanaTransaction.mockSwapValidatorTransaction()
        let rawInstruction = transaction.message.instructions[2]
        let instruction = try SwapValidatorProgram.PreSwap(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.preSwapState.base58, "4Zk9E4HaVBJKnukv2nV8aZQ1ZhqJCs74GaTyXBmPXBN6")
        XCTAssertEqual(instruction.user.base58, "6SLCvHRtnB1UJJN7RmHKq6aJ6Ugo5aQEswQ9f9wgybxy")
        XCTAssertEqual(instruction.source.base58, "5nNBW1KhzHVbR4NMPLYPRYj3UN5vgiw5GrtpdK6eGoce")
        XCTAssertEqual(instruction.destination.base58, "9Rgx4kjnYZBbeXXgbbYLT2FfgzrNHFUShDtp8dpHHjd2")
        XCTAssertEqual(instruction.nonce.base58, "2uZYLABYpqCAqE2PHa1nzpVRpy3aB8fUv293y6MQxm1Z")
        XCTAssertEqual(instruction.payer.base58, "swapBMF2EzkHSn9NDwaSFWMtGC7ZsgzApQv9NSkeUeU")
        XCTAssertEqual(instruction.remainingAccounts.count, 12)
    }
    
    func testDecodePostSwap() throws {
        let (transaction, _) = SolanaTransaction.mockSwapValidatorTransaction()
        let rawInstruction = transaction.message.instructions[4]
        let instruction = try SwapValidatorProgram.PostSwap(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.stateBump, 254)
        XCTAssertEqual(instruction.maxToSend, 10000)
        XCTAssertEqual(instruction.minToReceive, 57277492)
        XCTAssertEqual(instruction.preSwapState.base58, "4Zk9E4HaVBJKnukv2nV8aZQ1ZhqJCs74GaTyXBmPXBN6")
        XCTAssertEqual(instruction.source.base58, "5nNBW1KhzHVbR4NMPLYPRYj3UN5vgiw5GrtpdK6eGoce")
        XCTAssertEqual(instruction.destination.base58, "9Rgx4kjnYZBbeXXgbbYLT2FfgzrNHFUShDtp8dpHHjd2")
        XCTAssertEqual(instruction.payer.base58, "swapBMF2EzkHSn9NDwaSFWMtGC7ZsgzApQv9NSkeUeU")
    }
    
    func testDecodeComputeUnitLimit() throws {
        let (transaction, _) = SolanaTransaction.mockSwapValidatorTransaction()
        let rawInstruction = transaction.message.instructions[0]
        let instruction = try ComputeBudgetProgram.SetComputeUnitLimit(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.limit, 1400000)
    }
    
    func testDecodeComputeUnitPrice() throws {
        let (transaction, _) = SolanaTransaction.mockSwapValidatorTransaction()
        let rawInstruction = transaction.message.instructions[1]
        let instruction = try ComputeBudgetProgram.SetComputeUnitPrice(instruction: rawInstruction)
        
        XCTAssertEqual(instruction.microLamports, 4206)
    }
}
