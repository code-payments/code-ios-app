//
//  StoredMintMetadata.swift
//  Code
//
//  Created by Dima Bart on 2025-07-04.
//

import Foundation
import FlipcashCore

struct StoredMintMetadata: Identifiable, Sendable, Equatable, Hashable {
    
    let mint: PublicKey
    let name: String
    let symbol: String
    let decimals: Int
    let bio: String?
    let imageURL: URL?
    let vmAddress: PublicKey?
    let vmAuthority: PublicKey?
    let lockDuration: Int?
    let currencyConfig: PublicKey?
    let liquidityPool: PublicKey?
    let seed: PublicKey?
    let authority: PublicKey?
    let mintVault: PublicKey?
    let coreMintVault: PublicKey?
    let coreMintFees: PublicKey?
    let supplyFromBonding: UInt64?
    let coreMintLocked: UInt64?
    let sellFeeBps: Int?
    
    let updatedAt: Date
    
    var id: PublicKey {
        mint
    }
    
    init(mint: PublicKey, name: String, symbol: String, decimals: Int, bio: String?, imageURL: URL?, vmAddress: PublicKey?, vmAuthority: PublicKey?, lockDuration: Int?, currencyConfig: PublicKey?, liquidityPool: PublicKey?, seed: PublicKey?, authority: PublicKey?, mintVault: PublicKey?, coreMintVault: PublicKey?, coreMintFees: PublicKey?, supplyFromBonding: UInt64?, coreMintLocked: UInt64?, sellFeeBps: Int?, updatedAt: Date) {
        self.mint = mint
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.bio = bio
        self.imageURL = imageURL
        self.vmAddress = vmAddress
        self.vmAuthority = vmAuthority
        self.lockDuration = lockDuration
        self.currencyConfig = currencyConfig
        self.liquidityPool = liquidityPool
        self.seed = seed
        self.authority = authority
        self.mintVault = mintVault
        self.coreMintVault = coreMintVault
        self.coreMintFees = coreMintFees
        self.supplyFromBonding = supplyFromBonding
        self.coreMintLocked = coreMintLocked
        self.sellFeeBps = sellFeeBps
        self.updatedAt = updatedAt
    }
}

//extension StoredMintMetadata {
//    enum Error: Swift.Error {
//        
//    }
//}
