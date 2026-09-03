//
//  Derive.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

public enum Derive {
    private static let hardenedOffset: Int64 = 0x8000_0000

    static func seedUsingBIP39(phrase: [String], password: String = "") -> Key64 {
        try! Key64(SharedDerivation.seed(mnemonic: phrase, passphrase: password))
    }

    public static func keyPairUsingBIP39(path: Path, phrase: [String], password: String = "") -> KeyPair {
        let seed = seedUsingBIP39(phrase: phrase, password: password)
        let hardenedIndexes = path.indexes.map { hardenedOffset + Int64($0.value) }
        let derivedKey = SharedDerivation.derivedKey(seed: seed.data, hardenedIndexes: hardenedIndexes)
        return KeyPair(seed: try! Seed32(derivedKey))
    }
}
