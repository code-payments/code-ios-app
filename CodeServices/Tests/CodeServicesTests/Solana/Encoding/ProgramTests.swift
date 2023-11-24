//
//  ProgramTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class ProgramsTests: XCTestCase {
    
    func testCreateAccount() {
        let keys = generateKeys(3)
        
        let instruction = SystemProgram.CreateAccount(
            subsidizer: keys[0].publicKey,
            address: keys[1].publicKey,
            owner: keys[2].publicKey,
            lamports: 12345,
            size: 67890
        ).instruction()
        
        let command = [Byte](repeating: 0, count: 4)
        let lamports = UInt64(12345).bytes
        let size = UInt64(67890).bytes
        
        XCTAssertEqual(command, [Byte](instruction.data[0..<4]))
        XCTAssertEqual(lamports, [Byte](instruction.data[4..<12]))
        XCTAssertEqual(size, [Byte](instruction.data[12..<20]))
        XCTAssertEqual(keys[2].publicKey.bytes, [Byte](instruction.data[20..<52]))
        
        let tx = SolanaTransaction(
            data: SolanaTransaction(payer: keys[0].publicKey, recentBlockhash: nil, instructions: instruction).encode()
        )
        
        XCTAssertNotNil(tx)
    }
    
    func testInitializeAccount() {
        let keys = generateKeys(3)

        let instruction = TokenProgram.InitializeAccount(
            account: keys[0].publicKey,
            mint: keys[1].publicKey,
            owner: keys[2].publicKey
        ).instruction()

        XCTAssertEqual(Byte(1), instruction.data[0])
        XCTAssertTrue(instruction.accounts[0].isSigner)
        XCTAssertTrue(instruction.accounts[0].isWritable)
        for i in 1..<4 {
            XCTAssertFalse(instruction.accounts[i].isSigner)
            XCTAssertFalse(instruction.accounts[i].isWritable)
        }
    }
    
    func testTransfer() {
        let keys = generateKeys(3)

        let instruction = TokenProgram.Transfer(
            owner: keys[2].publicKey,
            source: keys[0].publicKey,
            destination: keys[1].publicKey,
            kin: Kin(quarks: 123456789)
        ).instruction()

        let expectedAmount = UInt64(123456789).bytes

        XCTAssertEqual(Byte(3), instruction.data[0])
        XCTAssertEqual(expectedAmount, [Byte](instruction.data[1..<instruction.data.count]))

        XCTAssertFalse(instruction.accounts[0].isSigner)
        XCTAssertTrue(instruction.accounts[0].isWritable)
        XCTAssertFalse(instruction.accounts[0].isSigner)
        XCTAssertTrue(instruction.accounts[0].isWritable)

        XCTAssertTrue(instruction.accounts[2].isSigner)
        XCTAssertTrue(instruction.accounts[2].isWritable)
    }
    
    func testFindAssociateTokenAddress() throws {
        let wallet  = PublicKey(base58: "4uQeVj5tqViQh7yWWGStvkEG1Zmhx6uasJtWCJziofM")!
        let mint    = PublicKey(base58: "8opHzTAnfzRpPEx21XtnrVTX28YQuCpAjcn1PczScKh")!
        let address = PublicKey(base58: "H7MQwEzt97tUJryocn3qaEoy2ymWstwyEk1i9Yv3EmuZ")!
        
        let result = try XCTUnwrap(PublicKey.deriveAssociatedAccount(from: wallet, mint: mint))
        XCTAssertEqual(result.publicKey, address)
    }
    
    /// Reference: https://github.com/solana-labs/solana/blob/5548e599fe4920b71766e0ad1d121755ce9c63d5/sdk/program/src/pubkey.rs#L479
    func testDeriveAddress() throws {
        let program   = PublicKey(base58: "BPFLoader1111111111111111111111111111111111")!
        let publicKey = PublicKey(base58: "SeedPubey1111111111111111111111111111111111")!

        let result = try XCTUnwrap(PublicKey.deriveProgramAddress(program: program, seeds: [publicKey.data]))

        XCTAssertEqual(result, PublicKey(base58: "GUs5qLUfsEHkcMB9T38vjr18ypEhRuNWiePW2LoK4E3K")!)
    }
    
    // MARK: - Integer-to-Bytes -
    
    func testIntegerToBytes() {
        let a = 8365 as UInt16
        let b = 947615873 as UInt32
        let c = 2785782645274654389 as UInt64
        
        let bytesA = [173, 32] as [Byte]
        let bytesB = [129, 120, 123, 56] as [Byte]
        let bytesC = [181, 54, 11, 97, 142, 22, 169, 38] as [Byte]
        
        XCTAssertEqual(a.bytes, bytesA)
        XCTAssertEqual(b.bytes, bytesB)
        XCTAssertEqual(c.bytes, bytesC)
        
        XCTAssertEqual(UInt16(bytes: bytesA)!, a)
        XCTAssertEqual(UInt32(bytes: bytesB)!, b)
        XCTAssertEqual(UInt64(bytes: bytesC)!, c)

        XCTAssertEqual(UInt16(data: Data(bytesA))!, a)
        XCTAssertEqual(UInt32(data: Data(bytesB))!, b)
        XCTAssertEqual(UInt64(data: Data(bytesC))!, c)
    }
    
    // MARK: - Utilities -
    
    private func generateKeys(_ amount: Int) -> [KeyPair] {
        (0..<amount).map { _ in
            KeyPair.generate()!
        }
    }
}
