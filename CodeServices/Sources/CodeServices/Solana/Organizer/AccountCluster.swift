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
    public let timelockAccounts: TimelockDerivedAccounts
    
    init(index: Int = 0, authority: DerivedKey, legacy: Bool = false) {
        self.index = index
        self.authority = authority
        self.timelockAccounts = TimelockDerivedAccounts(owner: authority.keyPair.publicKey, legacy: legacy)
    }
}
