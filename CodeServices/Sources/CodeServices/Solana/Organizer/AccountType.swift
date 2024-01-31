//
//  AccountType.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public enum AccountType: Equatable, Codable, Hashable {
    
    case primary
    case incoming
    case outgoing
    case bucket(SlotType)
    case remoteSend
    case relationship(Domain)
    case swap
    
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
        case .swap:
            return .swap()
        }
    }
}

// MARK: - Derivation Paths -

/*
 
 Primary      - m/44'/501'/0/0
 
 Incoming     - m/44'/501'/0/0/i/2
 Outgoing     - m/44'/501'/0/0/i/3
 
 Relationship - m/44'/501'/0/0/0/0
 Swap         - m/44'/501'/0/0/1/0  *
 etc.         - m/44'/501'/0/0/2/0  *
 
 Bucket1      - m/44'/501'/0/0/0/1
 Bucket10     - m/44'/501'/0/0/0/10
 Bucket100    - m/44'/501'/0/0/0/100
 Bucket1k     - m/44'/501'/0/0/0/1000
 Bucket10k    - m/44'/501'/0/0/0/10000
 Bucket100k   - m/44'/501'/0/0/0/100000
 Bucket1m     - m/44'/501'/0/0/0/1000000

*/

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
    
    public static func swap() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/1'/0")!
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

// MARK: - Proto -

extension AccountType {
    var accountType: Code_Common_V1_AccountType {
        switch self {
        case .primary:
            return .primary
            
        case .incoming:
            return .temporaryIncoming
            
        case .outgoing:
            return .temporaryOutgoing
            
        case .bucket(let type):
            switch type {
            case .bucket1:    return .bucket1Kin
            case .bucket10:   return .bucket10Kin
            case .bucket100:  return .bucket100Kin
            case .bucket1k:   return .bucket1000Kin
            case .bucket10k:  return .bucket10000Kin
            case .bucket100k: return .bucket100000Kin
            case .bucket1m:   return .bucket1000000Kin
            }
            
        case .remoteSend:
            return .remoteSendGiftCard
            
        case .relationship:
            return .relationship
            
        case .swap:
            return .swap
        }
    }
    
    init?(_ accountType: Code_Common_V1_AccountType, relationship: Code_Common_V1_Relationship?) {
        switch accountType {
        case .primary:
            self = .primary
        case .legacyPrimary2022:
            self = .primary
        case .temporaryIncoming:
            self = .incoming
        case .temporaryOutgoing:
            self = .outgoing
        case .bucket1Kin:
            self = .bucket(.bucket1)
        case .bucket10Kin:
            self = .bucket(.bucket10)
        case .bucket100Kin:
            self = .bucket(.bucket100)
        case .bucket1000Kin:
            self = .bucket(.bucket1k)
        case .bucket10000Kin:
            self = .bucket(.bucket10k)
        case .bucket100000Kin:
            self = .bucket(.bucket100k)
        case .bucket1000000Kin:
            self = .bucket(.bucket1m)
        case .remoteSendGiftCard:
            self = .remoteSend
        case .relationship:
            guard let relationship else {
                return nil
            }
            
            guard let domain = Domain(relationship.domain.value) else {
                return nil
            }
            
            self = .relationship(domain)
            
        case .swap:
            self = .swap
            
        case .unknown:
            return nil
        case .UNRECOGNIZED:
            return nil
        }
    }
}
