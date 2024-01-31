//
//  AccountCluster.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct AccountCluster: Equatable, Codable, Hashable {
    
    public let index: Int
    public let authority: DerivedKey
    public let derivation: Derivation
    
    public var authorityPublicKey: PublicKey {
        authority.keyPair.publicKey
    }
    
    public var vaultPublicKey: PublicKey {
        switch derivation {
        case .timelock(let timelock):
            return timelock.vault.publicKey
        case .usdc(let ata):
            return ata.ata.publicKey
        }
    }
    
    init(index: Int = 0, authority: DerivedKey, kind: Kind, legacy: Bool = false) {
        self.index = index
        self.authority = authority
        
        switch kind {
        case .timelock:
            self.derivation = .timelock(
                TimelockDerivedAccounts(owner: authority.keyPair.publicKey, legacy: legacy)
            )
            
        case .usdc:
            self.derivation = .usdc(
                AssociatedTokenAccount(owner: authority.keyPair.publicKey, mint: Mint.usdc)
            )
        }
    }
}

extension AccountCluster {
    public enum Kind {
        case timelock
        case usdc
    }
    
    public enum Derivation: Equatable, Codable, Hashable {
        case timelock(TimelockDerivedAccounts)
        case usdc(AssociatedTokenAccount)
    }
    
    public var timelock: TimelockDerivedAccounts? {
        if case .timelock(let v) = derivation {
            return v
        }
        return nil
    }
    
    public var ata: AssociatedTokenAccount? {
        if case .usdc(let v) = derivation {
            return v
        }
        return nil
    }
}
