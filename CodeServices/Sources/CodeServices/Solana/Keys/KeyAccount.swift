//
//  KeyAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct KeyAccount: Hashable, Equatable {
    
    public let mnemonic: MnemonicPhrase
    public let derivedKey: DerivedKey
    
    // MARK: - Init -
    
    public init(mnemonic: MnemonicPhrase, derivedKey: DerivedKey) {
        self.mnemonic   = mnemonic
        self.derivedKey = derivedKey
    }
}

extension KeyAccount {
    public var owner: KeyPair {
        derivedKey.keyPair
    }
    
    public var ownerPublicKey: PublicKey {
        owner.publicKey
    }
}

// MARK: - Derivation Paths -

extension Derive.Path {
    public static let solana  = Derive.Path("m/44'/501'/0'/0'")!
}

// MARK: - Mock -

extension MnemonicPhrase {
    public static let mock: MnemonicPhrase = {
        let words = "grant taste adapt picture build pact opinion ripple sock poet deposit snow".components(separatedBy: " ")
        return MnemonicPhrase(words: words)!
    }()
}

extension KeyPair {
    public static let mock: KeyPair = MnemonicPhrase.mock.solanaKeyPair()
}

extension KeyAccount {
    public static let mock: KeyAccount = {
        KeyAccount(
            mnemonic: .mock,
            derivedKey: DerivedKey(path: .solana, keyPair: .mock)
        )
    }()
}
