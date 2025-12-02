//
//  SolanaEncodingTests.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
import Foundation
import Testing
@testable import FlipcashCore

struct SolanaEncodingTests {
    
    @Test
    func testEncodingVersionedTransaction() throws {
        let keys = try generateKeys(amount: 8)
        let sortedKeys = keys.sorted { lhs, rhs in
            lhs.publicKey.data.lexicographicallyPrecedes(rhs.publicKey.data)
        }
        
        let payer = sortedKeys[0]
        let program = sortedKeys[1]
        let program2 = sortedKeys[2]
        let accountSigner = sortedKeys[3]
        let accountReadOnly = sortedKeys[4]
        let accountReadOnly2 = sortedKeys[5]
        let accountWritable = sortedKeys[6]
        let accountWritable2 = sortedKeys[7]
        
        var blockhashBytes = Data(count: 32)
        let status = blockhashBytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        #expect(status == errSecSuccess)
        
        let blockhash = try PublicKey(blockhashBytes)
        
        let ixn1Accounts: [AccountMeta] = [
            AccountMeta(publicKey: accountReadOnly.publicKey, signer: false, writable: false),
            AccountMeta(publicKey: accountReadOnly2.publicKey, signer: false, writable: false),
            AccountMeta(publicKey: accountWritable.publicKey, signer: false, writable: false),
            AccountMeta(publicKey: accountWritable2.publicKey, signer: false, writable: true)
        ]
        let ixn1 = Instruction(
            program: program.publicKey,
            accounts: ixn1Accounts,
            data: Data([0x01, 0x02, 0x03, 0x04])
        )
        
        let ixn2Accounts: [AccountMeta] = [
            AccountMeta(publicKey: accountWritable.publicKey, signer: false, writable: true),
            AccountMeta(publicKey: accountWritable.publicKey, signer: false, writable: false),
            AccountMeta(publicKey: accountReadOnly.publicKey, signer: false, writable: false),
            AccountMeta(publicKey: accountSigner.publicKey, signer: true, writable: false)
        ]
        let ixn2 = Instruction(
            program: program2.publicKey,
            accounts: ixn2Accounts,
            data: Data([0x05, 0x06, 0x07, 0x08])
        )
        let instructions = [ixn1, ixn2]
        
        let altKeys = try generateKeys(amount: 2)
        let sortedAltKeys = altKeys.sorted { lhs, rhs in
            lhs.publicKey.data.lexicographicallyPrecedes(rhs.publicKey.data)
        }
        
        let alts: [AddressLookupTable] = [
            AddressLookupTable(
                publicKey: sortedAltKeys[1].publicKey,
                addresses: [
                    payer.publicKey,
                    program.publicKey,
                    program2.publicKey,
                    accountReadOnly.publicKey,
                    accountReadOnly2.publicKey,
                    accountWritable.publicKey,
                    accountWritable2.publicKey
                ]
            ),
            AddressLookupTable(
                publicKey: sortedAltKeys[0].publicKey,
                addresses: [
                    accountSigner.publicKey,
                    accountReadOnly.publicKey,
                    accountReadOnly.publicKey,
                    accountWritable.publicKey,
                    accountWritable.publicKey
                ]
            )
        ]
        
        var tx = SolanaTransaction(
            payer: payer.publicKey,
            recentBlockhash: blockhash,
            addressLookupTables: alts,
            instructions: instructions
        )
        
        try tx.sign(using: payer, accountSigner)
        
        #expect(tx.signatures.count == 2)
        
        let message = tx.message
        
        #expect(message.accountKeys.count == 4)
        #expect(message.addressTableLookups.count == 2)
        
        let header = message.header
        #expect(header.requiredSignatures == 2)
        #expect(header.readOnlySigners == 1)
        #expect(header.readOnly == 2)
        
        #expect(message.recentBlockhash == blockhash)
        
        let messageData = message.encode()
        #expect(payer.verify(signature: tx.signatures[0], data: messageData) == true)
        #expect(accountSigner.verify(signature: tx.signatures[1], data: messageData) == true)
        
        #expect(message.version == .v0)
        
        #expect(message.accountKeys[0] == payer.publicKey)
        #expect(message.accountKeys[1] == accountSigner.publicKey)
        #expect(message.accountKeys[2] == program.publicKey)
        #expect(message.accountKeys[3] == program2.publicKey)
        
        let instr0 = message.instructions[0]
        #expect(instr0.programIndex == 2)
        #expect(instr0.data == Data([0x01, 0x02, 0x03, 0x04]))
        #expect(instr0.accountIndexes == [6, 7, 4, 5])
        
        let instr1 = message.instructions[1]
        #expect(instr1.programIndex == 3)
        #expect(instr1.data == Data([0x05, 0x06, 0x07, 0x08]))
        #expect(instr1.accountIndexes == [4, 4, 6, 1])
        
        let lookup0 = message.addressTableLookups[0]
        #expect(lookup0.publicKey == sortedAltKeys[0].publicKey)
        #expect(lookup0.readonlyIndexes == [1 as UInt8])
        #expect(lookup0.writableIndexes == [3 as UInt8])
        
        let lookup1 = message.addressTableLookups[1]
        #expect(lookup1.publicKey == sortedAltKeys[1].publicKey)
        #expect(lookup1.readonlyIndexes == [4 as UInt8])
        #expect(lookup1.writableIndexes == [6 as UInt8])
        
        print(tx.encode().base64EncodedString())
    }
    
    @Test
    func testRoundTrip() throws {
        let expected = "Abyp+nvyM7ZEdWoZTeADD5Cz8QJVVjhTr6CnzVj/CX2MwosyMNzT0tVNJ3gIUo8qxW8V+KclAAntCexlsvc2TQiAAQAEBYNezk00yE7eeJ8KVQSTMRnfgqKr2TuCkI2OvY6VqupmBqfVFxksVo7gioRfc9KXiM8DXDFFshqzRNgGLqlAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMGRm/lIRcy/+ytunLDm+e8jOW7xfcSayxDmzpAAAAAmu3bzcyfl+oHt1b29uzQvgBqO8OA3K6s5S0u4S+oQYqcHxhrhTySMLI0fOjClaCEkXjCshHIi9E63Co6m/5ZfgQCAwcBAAQEAAAAAwAFAkANAwADAAkD6AMAAAAAAAAEBQUGCAkKCgABAgMEBQYHCAkBtCdbdeueeYQHgQ6Wzm4pItAtbgGigO5L8M2bbV6t3zoDAgMAAwQFBg=="
        
        let decoded = Data(base64Encoded: expected)!
        
        let txn = SolanaTransaction.init(data: decoded)!
        
        #expect(txn.encode().base64EncodedString() == expected)

    }
}

func generateKeys(amount: Int) throws -> [KeyPair] {
    var keys: [KeyPair] = []
    for _ in 0..<amount {
        keys.append(KeyPair.generate()!)
    }
    return keys
}
