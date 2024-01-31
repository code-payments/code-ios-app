//
//  RelationshipBox.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

struct RelationshipBox: Equatable, Codable, Hashable {
    
    private(set) var publicKeys: [PublicKey: Relationship] = [:]
    private(set) var domains: [Domain: Relationship] = [:]
    
    init() {}
    
    func relationships(largestFirst: Bool = true) -> [Relationship] {
        domains.values.sorted { lhs, rhs in
            if largestFirst {
                return lhs.partialBalance > rhs.partialBalance
            } else {
                return lhs.partialBalance < rhs.partialBalance
            }
        }
    }
    
    func relationship(for publicKey: PublicKey) -> Relationship? {
        publicKeys[publicKey]
    }
    
    func relationship(for domain: Domain) -> Relationship? {
        domains[domain]
    }
    
    mutating func insert(_ relationship: Relationship) {
        publicKeys[relationship.cluster.vaultPublicKey] = relationship
        domains[relationship.domain] = relationship
    }
    
    mutating func remove(publicKey: PublicKey) {
        guard let relationship = publicKeys[publicKey] else {
            return
        }
        
        publicKeys.removeValue(forKey: publicKey)
        domains.removeValue(forKey: relationship.domain)
    }
    
    mutating func remove(domain: Domain) {
        guard let relationship = domains[domain] else {
            return
        }
        
        publicKeys.removeValue(forKey: relationship.cluster.vaultPublicKey)
        domains.removeValue(forKey: domain)
    }
}
