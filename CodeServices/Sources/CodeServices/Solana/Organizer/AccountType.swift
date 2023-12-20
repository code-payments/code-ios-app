//
//  AccountType.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum AccountType: Equatable, Codable, Hashable {
    
    case primary
    case incoming
    case outgoing
    case bucket(SlotType)
    case remoteSend
    case relationship(Domain)
    
    var slot: SlotType? {
        if case .bucket(let slot) = self {
            return slot
        }
        return nil
    }
    
    func derivationPath(using index: Int) -> Derive.Path {
        switch self {
        case .primary:
            return .primary()
        case .incoming:
            return .bucketIncoming(using: index)
        case .outgoing:
            return .bucketOutgoing(using: index)
        case .bucket(let slotType):
            return slotType.derivationPath
        case .remoteSend:
            // Remote send accounts are standard Solana accounts
            // and should use a standard derivation path that
            // would be compatible with other 3rd party wallets
            return .primary()
        case .relationship(let domain):
            return .relationship(domain: domain.relationshipHost)
        }
    }
}

// MARK: - Derivation Paths -

extension Derive.Path {
    
    public static func primary() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'")!
    }
    
    public static func bucketIncoming(using index: Int) -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/\(index)'/2")!
    }
    
    public static func bucketOutgoing(using index: Int) -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/\(index)'/3")!
    }
    
    public static func relationship(domain: String) -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/0", password: domain)!
    }
    
    public static func bucket1() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/1")!
    }
    
    public static func bucket10() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/10")!
    }
    
    public static func bucket100() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/100")!
    }
    
    public static func bucket1k() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/1000")!
    }
    
    public static func bucket10k() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/10000")!
    }
    
    public static func bucket100k() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/100000")!
    }
    
    public static func bucket1m() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/1000000")!
    }
}
