//
//  AccountMeta.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct AccountMeta: Equatable, Hashable, Codable, Sendable {
    
    public var publicKey: PublicKey
    public var isSigner: Bool
    public var isWritable: Bool
    public var isPayer: Bool
    public var isProgram: Bool
    
    internal init(publicKey: PublicKey, signer: Bool, writable: Bool, payer: Bool = false, program: Bool = false) {
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
        
        if lhs.isProgram != rhs.isProgram {
            return !lhs.isProgram
        }
        
        if lhs.isSigner != rhs.isSigner {
            return lhs.isSigner
        }
        
        if lhs.isWritable != rhs.isWritable {
            return lhs.isWritable
        }
        
        return lhs.publicKey.bytes.lexicographicallyPrecedes(rhs.publicKey.bytes)
    }
}

// MARK: - Array [AccountMeta] -

extension Array where Element == AccountMeta {
    
    /// Provide a unique set by publicKey of AccountMeta
    /// with the highest write permission.
    func filterUniqueAccounts() -> [AccountMeta] {
        var container: [AccountMeta] = []
        for account in self {
            var found = false
            
            for (index, existingAccount) in container.enumerated() {
                if account.publicKey == existingAccount.publicKey {
                    var updatedAccount = existingAccount
                    
                    // Promote the existing account to writable if applicable
                    if account.isSigner {
                        updatedAccount.isSigner = true
                    }
                    
                    if account.isWritable {
                        updatedAccount.isWritable = true
                    }
                    
                    if account.isPayer {
                        updatedAccount.isPayer = true
                    }
                    
                    if account.isProgram {
                        updatedAccount.isProgram = true
                    }
                    
                    container[index] = updatedAccount
                    found = true
                    break
                }
            }
            
            if !found {
                container.append(account)
            }
        }
        
        return container
    }
}

