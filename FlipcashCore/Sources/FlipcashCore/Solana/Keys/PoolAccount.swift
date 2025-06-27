//
//  PoolAccount.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-06-26.
//

import Foundation

public struct PoolAccount: Codable, Hashable, Equatable {

    public let index: Int
    public let rendezvous: KeyPair
    public let cluster: AccountCluster
    public let date: Date

    public init(mnemonic: MnemonicPhrase, index: Int) {
        self.init(
            rendezvous: DerivedKey.derive(
                using: .poolRendezvous(index: index),
                mnemonic: mnemonic
            ).keyPair,
            index: index,
            cluster: AccountCluster(
                authority: .derive(
                    using: .pool(index: index),
                    mnemonic: mnemonic
                )
            )
        )
    }

    private init(rendezvous: KeyPair, index: Int, cluster: AccountCluster) {
        self.rendezvous = rendezvous
        self.index      = index
        self.cluster    = cluster
        self.date       = .now
    }
}
