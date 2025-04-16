//
//  CompactMessage.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-11-14.
//

import Foundation

struct CompactMessage {
    
    var data: Data
    
    // MARK: - Init -
    
    init() {
        self.data = Data()
    }
    
    mutating func append(utf8: String) {
        data.append(Data(utf8.utf8))
    }
    
    mutating func append(data moreData: Data) {
        data.append(moreData)
    }
    
    mutating func append(publicKey: PublicKey) {
        data.append(publicKey.data)
    }
    
    mutating func append(fiat: Fiat) {
        data.append(contentsOf: fiat.quarks.bytes)
    }
    
    func signature(owner: KeyPair) -> Signature {
        let hash = SHA256.digest(data)
        return Signature(owner.sign(hash).data)!
    }
}
