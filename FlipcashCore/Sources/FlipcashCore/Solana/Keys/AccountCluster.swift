//
//  AccountCluster.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct AccountCluster: Equatable, Codable, Hashable, Sendable {
    
    public let authority: DerivedKey
    public let timelock: TimelockDerivedAccounts
    
    public var authorityPublicKey: PublicKey {
        authority.keyPair.publicKey
    }
    
    public var vaultPublicKey: PublicKey {
        timelock.vault.publicKey
    }
    
    public var depositPublicKey: PublicKey {
        timelock.deposit.publicKey
    }
    
    public init(authority: DerivedKey, mint: PublicKey, timeAuthority: PublicKey) {
        self.authority = authority
        self.timelock  = TimelockDerivedAccounts(
            owner: authority.keyPair.publicKey,
            mint: mint,
            timeAuthority: timeAuthority
        )
    }
    
    public func use(mint: PublicKey, timeAuthority: PublicKey) -> AccountCluster {
        AccountCluster(
            authority: authority,
            mint: mint,
            timeAuthority: timeAuthority
        )
    }
}

extension AccountCluster {
    public static let mock = AccountCluster(
        authority: .derive(using: .primary(), mnemonic: .mock),
        mint: .mock,
        timeAuthority: .usdcAuthority
    )
}
