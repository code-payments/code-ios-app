//
//  MerkleProof.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension PublicKey {
    public func verifyContained(in merkleRoot: Hash, using proof: [PublicKey]) -> Bool {
        data.verifyContained(in: merkleRoot, using: proof)
    }
}

extension Data {
    func verifyContained(in merkleRoot: Hash, using proof: [PublicKey]) -> Bool {
        var hash = SHA256.digest(self)
        
        let proofNodes = proof.map { $0.data }
        proofNodes.forEach { n in
            if hash.lexicographicallyPrecedes(n) || hash == n {
                hash = SHA256.digest(hash + n)
            } else {
                hash = SHA256.digest(n + hash)
            }
        }
        
        return hash == merkleRoot.data
    }
}
