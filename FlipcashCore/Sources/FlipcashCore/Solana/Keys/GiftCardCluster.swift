//
//  GiftCardCluster.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-29.
//

import Foundation

public struct GiftCardCluster: Equatable, Codable, Hashable, Sendable {
    
    public let mnemonic: MnemonicPhrase
    public let cluster: AccountCluster
    
    public init(mnemonic: MnemonicPhrase? = nil) {
        let mnemonicPhrase = mnemonic ?? MnemonicPhrase.generate(.words12)
        self.init(
            mnemonic: mnemonicPhrase,
            cluster: AccountCluster(
                authority: .derive(using: .solana, mnemonic: mnemonicPhrase)
            )
        )
    }
    
    private init(mnemonic: MnemonicPhrase, cluster: AccountCluster) {
        self.mnemonic = mnemonic
        self.cluster = cluster
    }
}
