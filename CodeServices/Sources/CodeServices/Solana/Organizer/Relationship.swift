//
//  Relationship.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Relationship: Equatable, Codable, Hashable {
    
    public var partialBalance: Kin
    
    public let cluster: AccountCluster
    
    public let domain: Domain
    
    // MARK: - Init -
    
    public init(partialBalance: Kin = 0, domain: Domain, mnemonic: MnemonicPhrase) {
        self.partialBalance = partialBalance
        self.domain = domain
        self.cluster = AccountCluster(
            authority: .derive(using: .relationship(domain: domain.relationshipHost),
            mnemonic: mnemonic)
        )
    }
}
