//
//  SolanaTransaction.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

/**
    Signature: [64]byte
    PublicKey: [32]byte
    Hash:      [32]byte
    CompiledInstruction:
        program_id_index: byte            // index of the program account in message::AccountKeys
        accounts:         short_vec<byte> // ordered indices mapping to message::AccountKeys to input to program
        data:             short_vec<byte> // raw data
    Transaction:
        signature: short_vec<Signature>
        Message:
            Header:
                num_required_signatures:        byte
                num_readonly_signed_accounts:   byte
                num_readonly_unsigned_accounts: byte
            AccountKeys:     short_vec<PublicKey>
            RecentBlockHash: Hash
            Instructions:    short_vec<CompiledInstruction>
    Serialization:
        - Arrays: No length, just elements.
        - ShortVec: ShortVec encoded length, then elements
        - Byte: Byte
        - Structs: Fields are serialized in order as declared. No metadata about structs are serialized.
*/
public struct SolanaTransaction: Equatable {
    
    public var message: Message
    public var signatures: [Signature]
    
    public var recentBlockhash: Hash {
        get {
            message.recentBlockhash
        }
        set {
            message.recentBlockhash = newValue
        }
    }
    
    public var identifier: Signature {
        signatures[0]
    }
    
    // MARK: - Init -
    
    internal init(message: Message, signatures: [Signature]) {
        self.signatures = signatures
        self.message = message
    }
    
    public init(payer: PublicKey, recentBlockhash: Hash?, instructions: Instruction...) {
        self.init(
            payer: payer,
            recentBlockhash: recentBlockhash,
            instructions: instructions
        )
    }
    
    public init(payer: PublicKey, recentBlockhash: Hash?, instructions: [Instruction]) {
        var accounts: [AccountMeta] = []
        
        accounts.append(
            .payer(publicKey: payer)
        )
        
        instructions.forEach {
            accounts.append(
                // Maybe needs to be .program()
                .program(publicKey: $0.program)
            )
            accounts.append(contentsOf: $0.accounts)
        }
        
        let message = Message(
            accounts: accounts,
            recentBlockhash: recentBlockhash ?? Hash.zero,
            instructions: instructions
        )
        
        self.init(
            message: message,
            signatures: .init(repeating: .zero, count: message.header.requiredSignatures)
        )
    }
    
    // MARK: - Signing -
    
    public func signature(using keyPair: KeyPair) -> Signature {
        keyPair.sign(message.encode())
    }
    
    @discardableResult
    public mutating func sign(using keyPairs: KeyPair...) throws -> [Signature] {
        let requiredSignatureCount = message.header.requiredSignatures
        if keyPairs.count > requiredSignatureCount {
            throw SigningError.tooManySigners
        }
        
        let messageData = message.encode()
        
        var signatures = [Signature](repeating: Signature.zero, count: requiredSignatureCount)
        
        self.signatures.enumerated().forEach { index, signature in
            signatures[index] = signature
        }
        
        var newSignatures: [Signature] = []
        for keyPair in keyPairs {
            guard let signatureIndex = message.accounts.firstIndex(where: { $0.publicKey == keyPair.publicKey }) else {
                throw SigningError.accountNotInAccountList("Account: \(keyPair.publicKey)")
            }
            
            let signature = keyPair.sign(messageData)
            signatures[signatureIndex] = signature
            newSignatures.append(signature)
        }
        
        self.signatures = signatures
        return newSignatures
    }
}

// MARK: - SolanaCodable -

extension SolanaTransaction {
    
    public init?(data: Data) {
        let (signatureCount, payload) = ShortVec.decodeLength(data)
        
        guard payload.count >= signatureCount * Signature.length else {
            return nil // Mismatched data
        }
        
        let signatures = payload.chunk(size: Signature.length, count: signatureCount) { Signature($0) }?.compactMap { $0 } ?? []
        let messageData = payload.tail(from: signatureCount * Signature.length)
        
        guard let message = Message(data: messageData) else {
            return nil
        }
        
        self.signatures = signatures
        self.message = message
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(
            ShortVec.encode(signatures.map { $0.data })
        )
        
        data.append(message.encode())
        
        return data
    }
}

// MARK: - Instructions -

extension SolanaTransaction {
    public func findInstruction<T>(type: T.Type) -> T? where T: InstructionType {
        for instruction in message.instructions {
            if let typed = try? T(instruction: instruction) {
                return typed
            }
        }
        return nil
    }
}

// MARK: - Error -

extension SolanaTransaction {
    public enum SigningError: Error {
        case tooManySigners
        case accountNotInAccountList(_ reason: String)
        case invalidKey
    }
}

// MARK: - Diff -

extension SolanaTransaction {
    func diff(comparedTo transaction: SolanaTransaction) {
        let lhs = self
        let rhs = transaction
        
        if lhs.identifier == rhs.identifier {
            printMatch(title: "ID")
        } else {
            printDiff(
                title: "ID",
                one: lhs.identifier.base58,
                two: rhs.identifier.base58
            )
        }
        
        if lhs.signatures == rhs.signatures {
            printMatch(title: "Signatures")
        } else {
            printDiff(
                title: "Signatures",
                one: lhs.signatures.map { $0.base58 },
                two: rhs.signatures.map { $0.base58 }
            )
        }
        
        if lhs.message.header == rhs.message.header {
            printMatch(title: "Header")
        } else {
            printDiff(
                title: "Header",
                one: lhs.message.header.description,
                two: rhs.message.header.description
            )
        }
        
        if lhs.message.recentBlockhash == rhs.message.recentBlockhash {
            printMatch(title: "Recent Blockhash")
        } else {
            printDiff(
                title: "Recent Blockhash",
                one: lhs.recentBlockhash.base58,
                two: rhs.recentBlockhash.base58
            )
        }
        
        if lhs.message.accounts == rhs.message.accounts {
            printMatch(title: "Accounts")
        } else {
            printDiff(
                title: "Accounts",
                one: lhs.message.accounts.map { $0.description },
                two: rhs.message.accounts.map { $0.description }
            )
        }
        
        if lhs.message.instructions == rhs.message.instructions {
            printMatch(title: "Instructions")
        } else {
            printDiff(
                title: "Instructions",
                one: lhs.message.instructions.map { $0.description },
                two: rhs.message.instructions.map { $0.description }
            )
        }
    }
    
    func printDiff(title: String, one: String, two: String) {
        printDiff(title: title, one: [one], two: [two])
    }
    
    func printDiff(title: String, one: [String], two: [String]) {
        let lineSeparator = "\n| -\n"
        
        print("✗ \(title)")
        print("|----------------------------------------------------------------------")
        
        let lines = (0..<max(one.count, two.count)).map { i in
            var oneValue = "-"
            if i < one.count {
                oneValue = one[i]
            }
            
            var twoValue = "-"
            if i < two.count {
                twoValue = two[i]
            }
            
            let content = """
            | 1: \(oneValue)
            | 2: \(twoValue)
            """
            
            return content
        }.joined(separator: lineSeparator)
        
        print(lines)
        print("|----------------------------------------------------------------------")
    }
    
    func printMatch(title: String) {
        print("✓ \(title)")
    }
}
