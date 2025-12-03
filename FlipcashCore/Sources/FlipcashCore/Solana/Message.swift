//
//  Message.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum Message: Equatable, Sendable {
    
    case legacy(LegacyMessage)
    case versionedV0(VersionedMessageV0)
    
    public var description: String {
        switch self {
        case .legacy(let m): return "LegacyMessage: \(m)"
        case .versionedV0(let m): return "VersionedMessageV0: \(m)"
        }
    }
    
    public var version: MessageVersion {
            switch self {
            case .legacy: return .legacy
            case .versionedV0: return .v0
            }
        }
    
    
    public var header: Header {
        switch self {
        case .legacy(let m): return m.header
        case .versionedV0(let m): return m.header
        }
    }
        
    public var accountKeys: [PublicKey] {
        switch self {
        case .legacy(let m): return m.accounts.map(\.publicKey)
        case .versionedV0(let m): return m.staticAccountKeys
        }
    }
    
    public var recentBlockhash: Hash {
        get {
            switch self {
            case .legacy(let m): return m.recentBlockhash
            case .versionedV0(let m): return m.recentBlockhash
            }
        }
        set {
            switch self {
            case .legacy(var m):
                m.recentBlockhash = newValue
                self = .legacy(m)
            case .versionedV0(var m):
                m.recentBlockhash = newValue
                self = .versionedV0(m)
            }
        }
    }
    
    public var instructions: [CompiledInstruction] {
        switch self {
        case .legacy(let m): return m.instructions.map { instruction in
            instruction.compile(using: accountKeys)
        }
        case .versionedV0(let m): return m.instructions
        }
    }
    
    public var versionDescription: String {
        switch self {
        case .legacy: return "Legacy"
        case .versionedV0: return "V0"
        }
    }
    
    public var addressTableLookups: [MessageAddressTableLookup] {
        switch self {
        case .versionedV0(let m): return m.addressTableLookups
        default: return []
        }
    }
}

extension Message {
    public init?(data: Data) {
        guard !data.isEmpty else {
            return nil
        }
        
        guard let firstByte = data.first else {
            return nil
        }
        
        let version: MessageVersion
        
        if firstByte < messageVersionSerializationOffset {
            version = .legacy
        } else if firstByte == MessageVersion.v0.rawValue + messageVersionSerializationOffset {
            version = .v0
        } else {
            return nil
        }
        
        trace(.note, components: "version: \(version)")
        
        switch version {
        case .legacy:
            guard let legacy = LegacyMessage(data: data) else {
                return nil
            }
            self = .legacy(legacy)
        case .v0:
            guard let v0 = VersionedMessageV0(data: data) else {
                return nil
            }
            self = .versionedV0(v0)
        }
    }
    
    public func encode() -> Data {
        switch self {
        case .legacy(let m): return m.encode()
        case .versionedV0(let m): return m.encode()
        }
    }
}
