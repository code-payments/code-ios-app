//
//  GiftCardAccount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct GiftCardAccount: Codable, Hashable, Equatable {
    
    public let mnemonic: MnemonicPhrase
    public let cluster: AccountCluster
    
    public init(mnemonic: MnemonicPhrase? = nil) {
        let mnemonicPhrase = mnemonic ?? MnemonicPhrase.generate(.words12)
        self.init(
            mnemonic: mnemonicPhrase,
            cluster: AccountCluster(
                authority: .derive(using: .solana, mnemonic: mnemonicPhrase),
                kind: .timelock
            )
        )
    }
    
    private init(mnemonic: MnemonicPhrase, cluster: AccountCluster) {
        self.mnemonic = mnemonic
        self.cluster = cluster
    }
}
