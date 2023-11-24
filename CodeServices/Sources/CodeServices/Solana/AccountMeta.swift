//
//  AccountMeta.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct AccountMeta {
    
    public var publicKey: PublicKey
    public var isSigner: Bool
    public var isWritable: Bool
    public var isPayer: Bool
    public var isProgram: Bool
    
    internal init(publicKey: PublicKey, signer: Bool, writable: Bool, payer: Bool, program: Bool) {
        self.publicKey = publicKey
        self.isSigner = signer
        self.isWritable = writable
        self.isPayer = payer
        self.isProgram = program
    }
    
    public static func payer(publicKey: PublicKey) -> AccountMeta {
        AccountMeta(
            publicKey: publicKey,
            signer: true,
            writable: true,
            payer: true,
            program: false
        )
    }
    
    public static func writable(publicKey: PublicKey, signer: Bool = false) -> AccountMeta {
        AccountMeta(
            publicKey: publicKey,
            signer: signer,
            writable: true,
            payer: false,
            program: false
        )
    }
    
    public static func readonly(publicKey: PublicKey, signer: Bool = false) -> AccountMeta {
        AccountMeta(
            publicKey: publicKey,
            signer: signer,
            writable: false,
            payer: false,
            program: false
        )
    }
    
    public static func program(publicKey: PublicKey) -> AccountMeta {
        AccountMeta(
            publicKey: publicKey,
            signer: false,
            writable: false,
            payer: false,
            program: true
        )
    }
}

extension AccountMeta: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let payer = isPayer ? "p" : ""
        let signer = isSigner ? "s" : ""
        let writable = isWritable ? "w" : ""
        let program = isProgram ? "p" : ""
        return "[\(payer)\(signer)\(writable)\(program)] \(publicKey.base58)"
    }
    
    public var debugDescription: String {
        description
    }
}

// MARK: - Comparable -

extension AccountMeta: Comparable {
    public static func <(lhs: AccountMeta, rhs: AccountMeta) -> Bool {
        if lhs.isPayer != rhs.isPayer {
            return lhs.isPayer
        }
        
        // Might need to move here
//        if lhs.isProgram != rhs.isProgram {
//            return !lhs.isProgram
//        }
        
        if lhs.isSigner != rhs.isSigner {
            return lhs.isSigner
        }
        
        if lhs.isWritable != rhs.isWritable {
            return lhs.isWritable
        }
        
        if lhs.isProgram != rhs.isProgram {
            return !lhs.isProgram
        }
        
        return lhs.publicKey.bytes.lexicographicallyPrecedes(rhs.publicKey.bytes)
    }
}
