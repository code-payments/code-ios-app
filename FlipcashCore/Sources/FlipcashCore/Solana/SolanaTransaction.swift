//
//  SolanaTransaction.swift
//  FlipchatServices
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
public struct SolanaTransaction: Equatable, Sendable {
    
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
        
        let legacy = LegacyMessage(
            accounts: accounts,
            recentBlockhash: recentBlockhash ?? Hash.zero,
            instructions: instructions
        )
        
        let message = Message.legacy(legacy)
        
        self.init(
            message: message,
            signatures: .init(repeating: .zero, count: message.header.requiredSignatures)
        )
    }
    
    // MARK: - V0 Init -
    public init(payer: PublicKey, recentBlockhash: Hash?, addressLookupTables: [AddressLookupTable], instructions: Instruction...) {
        self.init(
            payer: payer,
            recentBlockhash: recentBlockhash,
            addressLookupTables: addressLookupTables,
            instructions: instructions
        )
    }
        
    public init(payer: PublicKey, recentBlockhash: Hash?, addressLookupTables: [AddressLookupTable], instructions: [Instruction]) {
        let rb = recentBlockhash ?? Hash.zero
        
        // Build initial account metas
        var accountMetas: [AccountMeta] = [
            .payer(publicKey: payer)
        ]
        
        instructions.forEach { instruction in
            accountMetas.append(.program(publicKey: instruction.program))
            accountMetas.append(contentsOf: instruction.accounts)
        }
        
        // Filter unique and sort
        accountMetas = accountMetas.filterUniqueAccounts()
        
        accountMetas.sort { lhs, rhs in
            if lhs.isPayer { return true }
            if rhs.isPayer { return false }
            if lhs.isSigner != rhs.isSigner { return lhs.isSigner }
            if lhs.isWritable != rhs.isWritable { return lhs.isWritable }
            if lhs.isProgram != rhs.isProgram { return !lhs.isProgram }
            return lhs.publicKey < rhs.publicKey
        }
        
        // Sort LUTs by publicKey
        let sortedLUTs = addressLookupTables.sorted { $0.publicKey < $1.publicKey }
        
        // Prepare indexes
        var writableLUTIndexes: [[UInt8]] = Array(repeating: [], count: sortedLUTs.count)
        var readonlyLUTIndexes: [[UInt8]] = Array(repeating: [], count: sortedLUTs.count)
        
        // Build static keys and header
        var staticAccountKeys: [PublicKey] = []
        var header = Message.Header(
            requiredSignatures: 0,
            readOnlySigners: 0,
            readOnly: 0
        )
        
        for accountMeta in accountMetas {
            let pk = accountMeta.publicKey
            var isDynamicallyLoaded = false
            
            if !(accountMeta.isPayer || accountMeta.isSigner || accountMeta.isProgram) {
                for (lutIndex, lut) in sortedLUTs.enumerated() {
                    if let addressIndex = lut.addresses.firstIndex(of: pk) {
                        isDynamicallyLoaded = true
                        let byteIndex = UInt8(addressIndex)
                        if accountMeta.isWritable {
                            writableLUTIndexes[lutIndex].append(byteIndex)
                        } else {
                            readonlyLUTIndexes[lutIndex].append(byteIndex)
                        }
                        break
                    }
                }
            }
            
            if !isDynamicallyLoaded {
                staticAccountKeys.append(pk)
                
                if accountMeta.isSigner {
                    header.requiredSignatures += 1
                    if !accountMeta.isWritable {
                        header.readOnlySigners += 1
                    }
                } else if !accountMeta.isWritable {
                    header.readOnly += 1
                }
            }
        }
        
        print("writable lut count: \(writableLUTIndexes.count)")
        print("readable lut count: \(readonlyLUTIndexes.count)")
        
        // Build all accounts for instruction compilation: static + dynamic writable + dynamic readonly
        var allAccounts = staticAccountKeys
        for (lutIndex, lut) in sortedLUTs.enumerated() {
            for idx in writableLUTIndexes[lutIndex] {
                allAccounts.append(lut.addresses[Int(idx)])
            }
        }
        for (lutIndex, lut) in sortedLUTs.enumerated() {
            for idx in readonlyLUTIndexes[lutIndex] {
                allAccounts.append(lut.addresses[Int(idx)])
            }
        }
        
        // Build address table lookups
        var addressTableLookups: [MessageAddressTableLookup] = []
        for (lutIndex, lut) in sortedLUTs.enumerated() {
            let writable = writableLUTIndexes[lutIndex]
            let readonly = readonlyLUTIndexes[lutIndex]
            if !writable.isEmpty || !readonly.isEmpty {
                let lookup = MessageAddressTableLookup(
                    publicKey: lut.publicKey,
                    writableIndexes: writable,
                    readonlyIndexes: readonly
                )
                addressTableLookups.append(lookup)
            }
        }
        
        let compiledInstructions = instructions.map { instruction in
            instruction.compile(using: allAccounts)
        }
        
        let v0Message = VersionedMessageV0(
            header: header,
            staticAccountKeys: staticAccountKeys,
            recentBlockhash: rb,
            instructions: compiledInstructions,
            addressTableLookups: addressTableLookups
        )
        
        let message = Message.versionedV0(v0Message)
        
        self.init(
            message: message,
            signatures: Array(repeating: Signature.zero, count: Int(header.requiredSignatures))
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
            guard let signatureIndex = message.accountKeys.firstIndex(where: { $0 == keyPair.publicKey }) else {
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
        
        let signatures = payload.chunk(size: Signature.length, count: signatureCount) { try? Signature($0) }?.compactMap { $0 } ?? []
        let messageData = payload.tail(from: signatureCount * Signature.length)
        
        guard let message = Message(data: messageData) else {
            trace(.failure, components: "failed to unmarshal message")
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
//    public func findInstruction<T>(type: T.Type) -> T? where T: InstructionType {
//        for instruction in message.instructions {
//            if let typed = try? T(instruction: instruction) {
//                return typed
//            }
//        }
//        return nil
//    }
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
        
        if lhs.message.accountKeys == rhs.message.accountKeys {
            printMatch(title: "Accounts")
        } else {
            printDiff(
                title: "Accounts",
                one: lhs.message.accountKeys.map { $0.description },
                two: rhs.message.accountKeys.map { $0.description }
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
