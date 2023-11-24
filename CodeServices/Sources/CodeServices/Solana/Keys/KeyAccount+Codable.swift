//
//  KeyAccount+Codable.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension KeyAccount: Codable {
    
    public init(from decoder: Decoder) throws {
        let container    = try decoder.container(keyedBy: CodingKeys.self)
        
        let mnemonic     = try container.decode(MnemonicPhrase.self, forKey: .mnemonic)
        let derivedKey   = try container.decode(DerivedKey.self, forKey: .derivedKey)
        
        self.init(
            mnemonic: mnemonic,
            derivedKey: derivedKey
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(mnemonic,   forKey: .mnemonic)
        try container.encode(derivedKey, forKey: .derivedKey)
    }
}

extension KeyAccount {
    enum CodingKeys: String, CodingKey {
        case mnemonic
        case derivedKey
        case tokenAccount
    }
}
