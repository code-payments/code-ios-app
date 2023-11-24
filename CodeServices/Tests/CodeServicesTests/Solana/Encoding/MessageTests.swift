//
//  MessageTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class MessageTests: XCTestCase {
    
    func testMessageHeader() throws {
        let header = Message.Header(
            requiredSignatures: 2,
            readOnlySigners: 1,
            readOnly: 3
        )
        
        let data = header.encode()
        let decodedHeader = try XCTUnwrap(Message.Header(data: data))
        
        XCTAssertEqual(decodedHeader.requiredSignatures, 2)
        XCTAssertEqual(decodedHeader.readOnlySigners, 1)
        XCTAssertEqual(decodedHeader.readOnly, 3)
    }
    
    func testEncodeDecodeCycle() throws {
        
        let program = PublicKey.generate()!
        
        let program2 = PublicKey.generate()!
        
        let accounts: [AccountMeta] = [
            .payer(publicKey: .generate()!),
            .writable(publicKey: .generate()!),
            .readonly(publicKey: .generate()!),
        ]
        
        let accounts2: [AccountMeta] = [
            .writable(publicKey: .generate()!),
            .readonly(publicKey: .generate()!),
            .writable(publicKey: .generate()!),
            .readonly(publicKey: .generate()!),
        ]
        
        let instructions = [
            Instruction(
                program: program,
                accounts: accounts,
                data: Data([85, 73, 81, 94, 90, 23, 54, 12])
            ),
            Instruction(
                program: program2,
                accounts: accounts2,
                data: Data([81, 77, 95, 71, 86, 13, 34, 17])
            ),
        ]
        
        let blockhash = PublicKey.generate()!
        
        var allAccounts: [AccountMeta] = [
            .readonly(publicKey: program),
            .readonly(publicKey: program2),
        ]
        
        allAccounts.append(contentsOf: accounts)
        allAccounts.append(contentsOf: accounts2)
        
        let message = Message(
            accounts: allAccounts,
            recentBlockhash: blockhash,
            instructions: instructions
        )
        
        let data = message.encode()
        let decodedMessage = try XCTUnwrap(Message(data: data))
        
        XCTAssertEqual(decodedMessage.header, message.header)
        XCTAssertEqual(decodedMessage.accounts, allAccounts.sorted())
        XCTAssertEqual(decodedMessage.recentBlockhash, blockhash)
        XCTAssertEqual(decodedMessage.instructions, instructions)
    }
}
