//
//  TransactionEncodingTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class TransactionEncodingTests: XCTestCase {
    
    // Taken from: https://github.com/solana-labs/solana/blob/14339dec0a960e8161d1165b6a8e5cfb73e78f23/sdk/src/transaction.rs#L523
    let rustGenerated =
        "AUc7Cbu+gZalFSGeSFdukHhP7oSGaSdmdNEd5ZokaSysdoMWfI" +
        "OzjrAbdaBZZuDMAfyNAogAJdrhgVya+jthsgoBAAEDnON0wdcmjhYIDuXvd10F2qEjA" +
        "yEAJGSe/CGhYbk+WWMBAQEEBQYHCAkJCQkJCQkJCQkJCQkJCQkIBwYFBAEBAQICAgQF" +
        "BgcICQEBAQEBAQEBAQEBAQEBCQgHBgUEAgICAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
        "AAAAAAAAAAAABAgIAAQMBAgM="
    
    // The above example does not have the correct public key encoded in the keypair.
    // This is the above example with the correctly generated keypair.
    let rustGeneratedAdjusted =
        "ATMfBMZ8phHEheLph8K9TJhRKhnE4qNZvWiXdUdJRmlTCRsQjWmW2CkQJeRHBCcsqFm" +
        "2gynjL40M9mTe0Dxp4QIBAAEDfEya6wnC7f3Cv53qnOEywwIJ928rIdqAlfXYI1adXroBAQEEBQYHCA" +
        "kJCQkJCQkJCQkJCQkJCQkIBwYFBAEBAQICAgQFBgcICQEBAQEBAQEBAQEBAQEBCQgHBgUEAgICAAAAA" +
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAgIAAQMBAgM=="
    
    func testTransaction_CrossImpl() {
        let signerKey = "3053020101300506032b657004220420ff6524187c17a71584cc9b05b93a794b"
        let signerData = Data(fromHexEncodedString: signerKey)!
        let keypair = KeyPair(seed: Seed32(signerData)!)
        
        let programID = PublicKey([2, 2, 2, 4, 5, 6, 7, 8, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 8, 7, 6, 5, 4, 2, 2, 2])!
        
        let to = PublicKey([1, 1, 1, 4, 5, 6, 7, 8, 9, 9, 9, 9,9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8, 7, 6, 5, 4, 1, 1, 1])!
        
        let data = Data([1, 2, 3])
        
        var tx = SolanaTransaction(
            payer: keypair.publicKey,
            recentBlockhash: nil,
            instructions: Instruction(
                program: programID,
                accounts: [
                    .writable(publicKey: keypair.publicKey, signer: true),
                    .writable(publicKey: to, signer: false),
                ],
                data: data
            )
        )
        
        try! tx.sign(using: keypair)
        
        XCTAssertEqual(Data(base64Encoded: rustGeneratedAdjusted)!.hexEncodedString(), tx.encode().hexEncodedString())
    }
    
    
    
    func testTransaction_SingleInstruction() {
        var keys = keyPairs(0..<2)
        let payer = keys[0]
        let program = keys[1]
        
        keys = keyPairs(2..<6)
        let data = Data([1, 2, 3])
        
        let instructionAccounts: [AccountMeta] = [
            .readonly(publicKey: keys[0].publicKey, signer: true),
            .readonly(publicKey: keys[1].publicKey, signer: false),
            .writable(publicKey: keys[2].publicKey, signer: false),
            .writable(publicKey: keys[3].publicKey, signer: true),
        ]
        
        var tx = SolanaTransaction(
            payer: payer.publicKey,
            recentBlockhash: nil,
            instructions: Instruction(
                program: program.publicKey,
                accounts: instructionAccounts,
                data: data
            )
        )
        
        // Intentionally sign out of order to ensure ordering is fixed.
        let signatures = try! tx.sign(using: keys[0], keys[3], payer)
        
        XCTAssertEqual(tx.signatures.count, 3)
        XCTAssertEqual(tx.message.accounts.count, 6)
        XCTAssertEqual(3, tx.message.header.requiredSignatures)
        XCTAssertEqual(1, tx.message.header.readOnlySigners)
        XCTAssertEqual(2, tx.message.header.readOnly)
        
        let message = tx.message.encode()
        
        XCTAssertTrue(payer.verify(signature: tx.signatures[0], data: message))
        XCTAssertTrue(keys[3].verify(signature: tx.signatures[1], data: message))
        XCTAssertTrue(keys[0].verify(signature: tx.signatures[2], data: message))
        
        XCTAssertTrue(keys[0].verify(signature: signatures[0], data: message))
        XCTAssertTrue(keys[3].verify(signature: signatures[1], data: message))
        XCTAssertTrue(payer.verify(signature: signatures[2], data: message))
        
        XCTAssertEqual(payer.publicKey, tx.message.accounts[0].publicKey)
        XCTAssertEqual(keys[3].publicKey, tx.message.accounts[1].publicKey)
        XCTAssertEqual(keys[0].publicKey, tx.message.accounts[2].publicKey)
        XCTAssertEqual(keys[2].publicKey, tx.message.accounts[3].publicKey)
        XCTAssertEqual(keys[1].publicKey, tx.message.accounts[4].publicKey)
        XCTAssertEqual(program.publicKey, tx.message.accounts[5].publicKey)
        
        XCTAssertEqual(tx.message.instructions[0].program, program.publicKey)
        XCTAssertEqual(tx.message.instructions[0].data, data)
        XCTAssertEqual(tx.message.instructions[0].accounts, instructionAccounts)
    }
    
    func testTransaction_DuplicateKeys() {
        var keys = keyPairs(0..<2)
        let payer = keys[0]
        let program = keys[1]
        
        keys = keyPairs(2..<6)
        let data = Data([1, 2, 3])
        
        // Key[0]: ReadOnlySigner -> WritableSigner
        // Key[1]: ReadOnly       -> ReadOnlySigner
        // Key[2]: Writable       -> Writable       (ReadOnly,noop)
        // Key[3]: WritableSigner -> WritableSignera (ReadOnly,noop)
        
        let instructionAccounts: [AccountMeta] = [
            .readonly(publicKey: keys[0].publicKey, signer: true),
            .readonly(publicKey: keys[1].publicKey, signer: false),
            .writable(publicKey: keys[2].publicKey, signer: false),
            .writable(publicKey: keys[3].publicKey, signer: true),
            
            // Upgrade keys [0] and [1]
            .writable(publicKey: keys[0].publicKey, signer: false),
            .readonly(publicKey: keys[1].publicKey, signer: true),
            
            // 'Downgrade' keys [2] and [3] (noop)
            .readonly(publicKey: keys[2].publicKey, signer: false),
            .readonly(publicKey: keys[3].publicKey, signer: false),
        ]
        
        var tx = SolanaTransaction(
            payer: payer.publicKey,
            recentBlockhash: nil,
            instructions: [
                Instruction(
                    program: program.publicKey,
                    accounts: instructionAccounts,
                    data: data
                )
            ]
        )
        
        // Intentionally sign out of order to ensure ordering is fixed.
        let signatures = try! tx.sign(using: keys[0], keys[1], keys[3], payer)
        
        XCTAssertEqual(tx.signatures.count, 4)
        XCTAssertEqual(tx.message.accounts.count, 6)
        XCTAssertEqual(4, tx.message.header.requiredSignatures)
        XCTAssertEqual(1, tx.message.header.readOnlySigners)
        XCTAssertEqual(1, tx.message.header.readOnly)
        
        let message = tx.message.encode()
        
        XCTAssertTrue(payer.verify(signature: tx.signatures[0], data: message))
        XCTAssertTrue(keys[0].verify(signature: tx.signatures[1], data: message))
        XCTAssertTrue(keys[3].verify(signature: tx.signatures[2], data: message))
        XCTAssertTrue(keys[1].verify(signature: tx.signatures[3], data: message))
        
        XCTAssertTrue(keys[0].verify(signature: signatures[0], data: message))
        XCTAssertTrue(keys[1].verify(signature: signatures[1], data: message))
        XCTAssertTrue(keys[3].verify(signature: signatures[2], data: message))
        XCTAssertTrue(payer.verify(signature: signatures[3], data: message))
        
        XCTAssertEqual(payer.publicKey, tx.message.accounts[0].publicKey)
        XCTAssertEqual(keys[0].publicKey, tx.message.accounts[1].publicKey)
        XCTAssertEqual(keys[3].publicKey, tx.message.accounts[2].publicKey)
        XCTAssertEqual(keys[1].publicKey, tx.message.accounts[3].publicKey)
        XCTAssertEqual(keys[2].publicKey, tx.message.accounts[4].publicKey)
        XCTAssertEqual(program.publicKey, tx.message.accounts[5].publicKey)
        
        XCTAssertEqual(tx.message.instructions[0].program, program.publicKey)
        XCTAssertEqual(tx.message.instructions[0].data, data)
        XCTAssertEqual(tx.message.instructions[0].accounts, instructionAccounts)
    }
    
    func testTransaction_MultiInstruction() {
        var keys = keyPairs(0..<3)
        let payer = keys[0]
        let program = keys[1]
        let program2 = keys[2]
        
        keys = keyPairs(3..<9)
        
        let data  = Data([1, 2, 3])
        let data2 = Data([3, 4, 5])
        
        // Key[0]: ReadOnlySigner -> WritableSigner
        // Key[1]: ReadOnly       -> WritableSigner
        // Key[2]: Writable       -> Writable       (ReadOnly,noop)
        // Key[3]: WritableSigner -> WritableSigner (ReadOnly,noop)
        // Key[4]: n/a            -> WritableSigner
        // Key[5]: n/a            -> ReadOnly
        
        let instructionAccounts: [AccountMeta] = [
            .readonly(publicKey: keys[0].publicKey, signer: true),
            .readonly(publicKey: keys[1].publicKey, signer: false),
            .writable(publicKey: keys[2].publicKey, signer: false),
            .writable(publicKey: keys[3].publicKey, signer: true),
        ]
        
        let instruction2Accounts: [AccountMeta] = [
            // Ensure that keys don't get downgraded in permissions
            .readonly(publicKey: keys[3].publicKey, signer: false),
            .readonly(publicKey: keys[2].publicKey, signer: false),
            
            // Ensure we can upgrade upgrading works
            .writable(publicKey: keys[0].publicKey, signer: false),
            .writable(publicKey: keys[1].publicKey, signer: true),
            
            // Ensure accounts get added
            .writable(publicKey: keys[4].publicKey, signer: true),
            .readonly(publicKey: keys[5].publicKey, signer: false),
        ]
        
        var tx = SolanaTransaction(
            payer: payer.publicKey,
            recentBlockhash: nil,
            instructions: [
                Instruction(
                    program: program.publicKey,
                    accounts: instructionAccounts,
                    data: data
                ),
                Instruction(
                    program: program2.publicKey,
                    accounts: instruction2Accounts,
                    data: data2
                )
            ]
        )
        
        let signatures = try! tx.sign(using: payer, keys[0], keys[1], keys[3], keys[4])
        
        XCTAssertEqual(tx.signatures.count, 5)
        XCTAssertEqual(tx.message.accounts.count, 9)
        
        XCTAssertEqual(5, tx.message.header.requiredSignatures)
        XCTAssertEqual(0, tx.message.header.readOnlySigners)
        XCTAssertEqual(3, tx.message.header.readOnly)
        
        let message = tx.message.encode()
        
        XCTAssertTrue(payer.verify(signature: tx.signatures[0], data: message))
        XCTAssertTrue(keys[4].verify(signature: tx.signatures[1], data: message))
        XCTAssertTrue(keys[3].verify(signature: tx.signatures[2], data: message))
        XCTAssertTrue(keys[0].verify(signature: tx.signatures[3], data: message))
        XCTAssertTrue(keys[1].verify(signature: tx.signatures[4], data: message))
        
        XCTAssertTrue(payer.verify(signature: signatures[0], data: message))
        XCTAssertTrue(keys[0].verify(signature: signatures[1], data: message))
        XCTAssertTrue(keys[1].verify(signature: signatures[2], data: message))
        XCTAssertTrue(keys[3].verify(signature: signatures[3], data: message))
        XCTAssertTrue(keys[4].verify(signature: signatures[4], data: message))
        
        XCTAssertEqual(payer.publicKey, tx.message.accounts[0].publicKey)
        XCTAssertEqual(keys[4].publicKey, tx.message.accounts[1].publicKey)
        XCTAssertEqual(keys[3].publicKey, tx.message.accounts[2].publicKey)
        XCTAssertEqual(keys[0].publicKey, tx.message.accounts[3].publicKey)
        XCTAssertEqual(keys[1].publicKey, tx.message.accounts[4].publicKey)
        XCTAssertEqual(keys[2].publicKey, tx.message.accounts[5].publicKey)
        XCTAssertEqual(keys[5].publicKey, tx.message.accounts[6].publicKey)
        XCTAssertEqual(program2.publicKey, tx.message.accounts[7].publicKey)
        XCTAssertEqual(program.publicKey, tx.message.accounts[8].publicKey)
        
        XCTAssertEqual(tx.message.instructions[0].program, program.publicKey)
        XCTAssertEqual(tx.message.instructions[0].data, data)
        XCTAssertEqual(tx.message.instructions[0].accounts, instructionAccounts)
        
        XCTAssertEqual(tx.message.instructions[1].program, program2.publicKey)
        XCTAssertEqual(tx.message.instructions[1].data, data2)
        XCTAssertEqual(tx.message.instructions[1].accounts, instruction2Accounts)
    }
    
    func testTransation_UpdateSignature() {
        let transaction = createTransaction()
        
        XCTAssertEqual(transaction.signatures.count, 2)
        
        let signature = Signature([Byte](repeating: 0x33, count: 64))!
        var updatedTransaction = transaction
        updatedTransaction.signatures[0] = signature
        
        XCTAssertEqual(updatedTransaction.signatures.count, 2)
        XCTAssertEqual(updatedTransaction.signatures[0], signature)
        XCTAssertEqual(updatedTransaction.signatures[1], transaction.signatures[1])
    }
    
    func createTransaction() -> SolanaTransaction {
        let keys = keyPairs(0..<2)
        let tx = SolanaTransaction(
            payer: keys[0].publicKey,
            recentBlockhash: nil,
            instructions: [
                Instruction(
                    program: keys[1].publicKey,
                    accounts: [
                        .payer(publicKey: keys[0].publicKey),
                    ],
                    data: Data([5,6,7])
                )
            ]
        )
        
        let signatures = [
            Signature([Byte](repeating: 0x11, count: 64)),
            Signature([Byte](repeating: 0x22, count: 64)),
        ].compactMap { $0 }
        
        return SolanaTransaction(
            message: tx.message,
            signatures: signatures
        )
    }
    
    // MARK: - Keys -
    
    private var keys: [KeyPair] = {
        let seeds = [
            "ec7014c260ea0d1b7c94e20e647514f4b1a327f2ee589d0b08f484d99431f315",
            "4939003d35acc5cd2d50b4bd0dd094acea1add90eda1ebba94260cd85fcf36e1",
            "e6e0895e22a6f9eb7c35e04f110223b314a0dfe74508253cc702020135b609c6",
            "8a81bc0c3f313ce56c564b0ef5730c033883e81bbf25ba636b00c8a6f4dae856",
            "b18179a3bd36568e8b28c7e0174ecdd0916163fb02a720757a70284470363dd6",
            "7284328767e310a0ca293e48f863141b2ab6a2e7e3e266fcc4ccd579ed17cc29",
            "2d02e6304fffcda39c856acb6b8c4556e558eee4d4cbd27102a8cbfeb12f85db",
            "2765eca4213fa5fd330f065dd561969af71cb5e00529f18473e530311929697b",
            "cf1c6411ff7670e6a99c962e09fb8da1cd586669e5709e9fae7cf811eda73410",
            "10258fb6227090460d77ad21e4026a93c1e5b8ce8543c86ee469876d38626c1b",
            "e16cc7050349cb88f99671feeecb7c1a8813597f944fc2d2d73dcd997de9f32c",
            "2b4ddb00de37a47549f2e06625b47c4976c62edacfcaec11ec5afaf9105491aa",
            "87419c465c07b4f438a37f1bc02ea2f6cf5746c8626dac24c9ae82159012739d",
            "26e4b17a5e8c1624dd5cc2a424bff2e7c454dc5dc980168364669e9d731f1b8f",
            "bf0b47fad6b168333a2a4abd71fa57bb854d99bb76df7b4ee301236262266600",
            "eec7c6e41deff0baba12a5e923ed65d911b04565f624ff717c1b6ba71744766a",
            "c03b9e33b84b7264443b109723e9dcfadad98dad7a69d6f90622ecaf038c7a67",
            "76b9b990856b606fa5423958210f8b572b0379b716fd706ee8188993e25a8d70",
            "856824d5a94d1dbc47326262c51cf6be906e30d804b73a0d714c958d01f0c715",
            "807297cc956098ab30ea5e94be5329c7bc47fd636f3f5198f6ee8fe99289308a",
        ]
        
        return seeds.map { seedHex in
            let data = Data(fromHexEncodedString: seedHex)!
            let seed = Seed32(data)!
            return KeyPair(seed: seed)
        }
    }()

    private func keyPairs(_ range: Range<Int>) -> [KeyPair] {
        Array(keys[range])
    }
}
