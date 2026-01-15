//
//  VersionedMessage.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
import Foundation

public struct VersionedMessageV0: Equatable, Sendable {
    public let header: Message.Header
    public let staticAccountKeys: [PublicKey]
    public var recentBlockhash: Hash
    public let instructions: [CompiledInstruction]
    public let addressTableLookups: [MessageAddressTableLookup]
    
    public var description: String {
        "V0(header: \(header), staticKeys: \(staticAccountKeys.count), lookups: \(addressTableLookups.count))"
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(Byte(MessageVersion.v0.rawValue + messageVersionSerializationOffset))
        // message content
        // same as legacy
        data.append(header.encode())
        data.append(
            ShortVec.encode(staticAccountKeys.map { $0.data })
        )
        data.append(recentBlockhash.data)
        data.append(
            ShortVec.encode(instructions.map { $0.encode() })
        )
        
        data.append(ShortVec.encode(addressTableLookups.map { $0.encode() }))
        
        return data
    }
}

extension VersionedMessageV0 {
    public init?(data: Data) {
        guard !data.isEmpty else {
            trace(.failure, components: "data is empty \(data.count)")
            return nil
        }
        
        var payload = data
        
        // Message Version
        guard let version = payload.consume(1).first else {
            return nil
        }
        
        if version != MessageVersion.v0.rawValue + messageVersionSerializationOffset {
            trace(.failure, components: "version not v0")
            return nil
        }
        
        // Decode Header (manually, without decompiling instructions)
        guard let header = Message.Header(data: payload.consume(Message.Header.length)) else {
            trace(.failure, components: "failed to decode header")
            return nil
        }
        
        // Decode static account keys
        let (accountCount, accountData) = ShortVec.decodeLength(payload)
        trace(.note, components: "static account count: \(accountCount)")
        guard let staticKeys = accountData.chunk(size: PublicKey.length, count: accountCount, block: { try? PublicKey($0) })?.compactMap({ $0 }) else {
            trace(.failure, components: "failed to decode static account keys")
            return nil
        }
        
        payload = accountData.tail(from: PublicKey.length * accountCount)
        
        // Decode recent blockhash
        guard let hash = try? Hash(payload.consume(Hash.length)) else {
            trace(.failure, components: "failed to decode blockhash")
            return nil
        }
        
        // Decode compiled instructions (without decompiling yet)
        let (instructionCount, instructionsData) = ShortVec.decodeLength(payload)
        trace(.note, components: "instruction count: \(instructionCount)")
        
        var remainingInstructionData = instructionsData
        var compiledInstructions: [CompiledInstruction] = []
        
        for _ in 0..<instructionCount {
            guard let instruction = CompiledInstruction(data: remainingInstructionData) else {
                trace(.failure, components: "failed to decode compiled instruction")
                return nil
            }
            remainingInstructionData = remainingInstructionData.tail(from: instruction.byteLength)
            compiledInstructions.append(instruction)
        }
        
        payload = remainingInstructionData
        
        // Decode Address Table Lookups
        let (addressTableLookupLength, lookupData) = ShortVec.decodeLength(payload)
        var remaining = lookupData
        
        var addressTableLookups: [MessageAddressTableLookup] = []
        
        for _ in 0..<addressTableLookupLength {
            // Public Key
            guard remaining.count >= PublicKey.length else {
                trace(.failure, components: "not enough data for lookup public key")
                return nil
            }
            let publicKeyData = Data(remaining.prefix(PublicKey.length))
            remaining = remaining.dropFirst(PublicKey.length)
            guard let publicKey = try? PublicKey(publicKeyData) else {
                trace(.failure, components: "failed to decode lookup public key")
                return nil
            }
            
            // Writable indexes
            let (writableIndexesLength, writableRemaining) = ShortVec.decodeLength(remaining)
            remaining = writableRemaining
            
            guard remaining.count >= writableIndexesLength else {
                trace(.failure, components: "not enough data for writable indexes, need: \(writableIndexesLength), have: \(remaining.count)")
                return nil
            }
            let writableIndexes = Array(remaining.prefix(writableIndexesLength))
            remaining = remaining.dropFirst(writableIndexesLength)
            
            // Readonly indexes
            let (readonlyIndexesLength, readonlyRemaining) = ShortVec.decodeLength(remaining)
            remaining = readonlyRemaining
            
            guard remaining.count >= readonlyIndexesLength else {
                trace(.failure, components: "not enough data for readonly indexes, need: \(readonlyIndexesLength), have: \(remaining.count)")
                return nil
            }
            let readonlyIndexes = Array(remaining.prefix(readonlyIndexesLength))
            remaining = remaining.dropFirst(readonlyIndexesLength)
            
            // Create the lookup entry
            let lookup = MessageAddressTableLookup(
                publicKey: publicKey,
                writableIndexes: writableIndexes,
                readonlyIndexes: readonlyIndexes
            )
            addressTableLookups.append(lookup)
        }
        
        // Now we have everything, store it
        self.header = header
        self.staticAccountKeys = staticKeys
        self.recentBlockhash = hash
        self.instructions = compiledInstructions
        self.addressTableLookups = addressTableLookups
        
        trace(.note, components: "successfully deserialized V0 message")
    }
}
