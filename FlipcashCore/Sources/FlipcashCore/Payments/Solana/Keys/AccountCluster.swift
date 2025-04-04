//
//  AccountCluster.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct AccountCluster: Equatable, Codable, Hashable, Sendable {
    
    public let index: Int
    public let authority: DerivedKey
    public let timelock: TimelockDerivedAccounts
    
    public var authorityPublicKey: PublicKey {
        authority.keyPair.publicKey
    }
    
    public var vaultPublicKey: PublicKey {
        timelock.vault.publicKey
    }
    
    init(index: Int = 0, authority: DerivedKey) {
        self.index     = index
        self.authority = authority
        self.timelock  = TimelockDerivedAccounts(owner: authority.keyPair.publicKey)
    }
}
