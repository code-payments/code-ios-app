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
    public let mint: PublicKey
    
    public init(mnemonic: MnemonicPhrase? = nil, mint: PublicKey, timeAuthority: PublicKey) {
        let mnemonicPhrase = mnemonic ?? MnemonicPhrase.generate(.words12)
        self.init(
            mnemonic: mnemonicPhrase,
            cluster: AccountCluster(
                authority: .derive(using: .solana, mnemonic: mnemonicPhrase),
                mint: mint,
                timeAuthority: timeAuthority
            ),
            mint: mint
        )
    }
    
    private init(mnemonic: MnemonicPhrase, cluster: AccountCluster, mint: PublicKey) {
        self.mnemonic = mnemonic
        self.cluster  = cluster
        self.mint     = mint
    }
}
